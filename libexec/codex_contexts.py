#!/usr/bin/env python3
"""Data parsing and environment boundaries for the Bash launcher (Python 3.11+)."""
from __future__ import annotations

import os
from contextlib import contextmanager
import fcntl
import hashlib
import json
from pathlib import Path
import re
import shutil
import signal
import stat
import sys
import tempfile
try:
    import tomllib
except ModuleNotFoundError:
    print("codex-home: Python 3.11 or newer is required", file=sys.stderr)
    raise SystemExit(1)
from urllib.parse import urlsplit


def fail(message: str) -> None:
    raise ValueError(message)


def read_config(path: str | Path) -> dict:
    with open(path, "rb") as handle:
        return tomllib.load(handle)


def validate_url(url: object, *, field: str = "base URL", allow_query: bool = False) -> None:
    if not isinstance(url, str) or not url:
        fail(f"{field}: URL must be a nonempty string")
    if re.search(r"[\s\x00-\x1f\x7f\\]", url):
        fail(f"{field} must be a single URL without whitespace or backslashes")
    try:
        parts = urlsplit(url)
    except ValueError:
        fail(f"{field} is not a valid URL")
    if parts.scheme not in {"http", "https"} or not parts.netloc:
        fail(f"{field} must use HTTPS (HTTP is allowed only for loopback development)")
    if "@" in parts.netloc or "%" in parts.netloc or "#" in url:
        fail(f"{field} may not contain user information or a fragment")
    if not allow_query and "?" in url:
        fail(f"{field} may not contain a query")
    if not parts.hostname:
        fail(f"{field} requires a host")
    try:
        port = parts.port
    except ValueError:
        fail(f"{field} has an invalid port")
    if port == 0 or parts.netloc.endswith(":"):
        fail(f"{field} has an invalid port")
    if parts.scheme == "http" and not re.fullmatch(
        r"(?:localhost|127\.0\.0\.1|\[::1\])(?::[0-9]+)?", parts.netloc, re.IGNORECASE
    ):
        fail(f"{field}: remote providers require HTTPS; HTTP is allowed only for localhost, 127.0.0.1, or [::1]")


def key_name(value: str) -> str:
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", value):
        fail("invalid API-key environment-variable name")
    if blocked_variable(value) or value in SAFE_ENV or value.startswith("LC_") or value.startswith("CODEX_"):
        fail("API-key variable may not replace a runtime or launcher variable")
    return value


def selected_provider(home: str | Path) -> tuple[dict, str, dict]:
    config = read_config(Path(home) / "config.toml")
    provider_name = config.get("model_provider", "openai")
    providers = config.get("model_providers", {})
    if not isinstance(provider_name, str) or not isinstance(providers, dict):
        fail("model_provider and model_providers have invalid types")
    provider = providers.get(provider_name, {})
    if not isinstance(provider, dict):
        fail("selected provider must be a TOML table")
    # Key lookup and model discovery also use this path, without launch_check.
    validate_config_urls(config)
    return config, provider_name, provider


def managed_auth(home: str | Path, name: str) -> dict:
    """Native command authentication, with no secret in arguments or environment."""
    return {
        "command": os.path.abspath(shutil.which("python3") or sys.executable),
        "args": ["-I", str(Path(__file__).resolve()), "credential", str(Path(home).resolve()), key_name(name)],
        "timeout_ms": 5000,
        "refresh_interval_ms": 0,
    }


def auth_toml(home: str | Path, name: str) -> str:
    values = managed_auth(home, name)
    return "{ " + ", ".join(f"{key} = {json.dumps(value, ensure_ascii=False)}" for key, value in values.items()) + " }"


def managed_key_name(home: str | Path, provider: dict) -> str:
    auth = provider.get("auth", {})
    if not isinstance(auth, dict):
        return ""
    args = auth.get("args", [])
    if (not isinstance(args, list) or len(args) < 3 or args[2] != "credential"
            or not isinstance(args[1], str) or Path(args[1]).name != "codex_contexts.py"):
        return ""
    command = auth.get("command")
    valid = (
        len(args) == 5 and all(isinstance(value, str) for value in args)
        and args[0] == "-I" and Path(args[1]).is_absolute()
        and Path(args[1]).is_file() and Path(args[1]).parent.name == "libexec"
        and Path(args[3]).is_absolute() and Path(args[3]).resolve() == Path(home).resolve()
        and isinstance(command, str) and Path(command).is_absolute() and Path(command).is_file() and os.access(command, os.X_OK)
        and auth.keys() == {"command", "args", "timeout_ms", "refresh_interval_ms"}
        and type(auth["timeout_ms"]) is int and auth["timeout_ms"] == 5000
        and type(auth["refresh_interval_ms"]) is int and auth["refresh_interval_ms"] == 0
    )
    if not valid:
        fail("unrecognized managed credential command; restore its generated authentication settings")
    if "env_key" in provider or provider.get("requires_openai_auth") or "experimental_bearer_token" in provider:
        fail("managed credential command may not be combined with other primary authentication")
    return key_name(args[4])


def credential_key_name(home: str | Path, provider: dict) -> str:
    managed = managed_key_name(home, provider)
    name = provider.get("env_key", "")
    return managed or (key_name(name) if name else "")


def selected_key_name(home: str | Path) -> str:
    _, _, provider = selected_provider(home)
    return credential_key_name(home, provider)


@contextmanager
def credential_lock(home: str | Path):
    """Serialize key replacement and configuration/key migration in one home."""
    path = Path(home) / ".api-auth.lock"
    fd = os.open(path, os.O_CREAT | os.O_RDWR | os.O_NOFOLLOW | os.O_NONBLOCK, 0o600)
    try:
        opened = os.fstat(fd)
        named = path.lstat()
        if (not stat.S_ISREG(opened.st_mode) or opened.st_uid != os.getuid()
                or opened.st_nlink != 1 or opened.st_mode & 0o022
                or (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino)):
            fail("refusing an unsafe credential lock")
        fcntl.flock(fd, fcntl.LOCK_EX)
        named = path.lstat()
        if (opened.st_dev, opened.st_ino) != (named.st_dev, named.st_ino):
            fail("credential lock changed while waiting")
        yield
    finally:
        os.close(fd)


def credential_path(home: str | Path, provider: dict) -> Path:
    return Path(home) / ("api-key.env" if managed_key_name(home, provider) else ".env")


def reject_legacy_dotenv(home: str | Path) -> None:
    legacy = Path(home) / ".env"
    if legacy.exists() or legacy.is_symlink():
        fail("managed identity still has .env, which Codex automatically exports; run migrate-api-auth or inspect/remove that legacy file")


def store_key(home: str, name: str, secret: str) -> str:
    """Write one literal key, without exposing it in a child environment/argv."""
    if not secret or any(ord(char) < 32 or ord(char) == 127 for char in secret):
        fail("API key must be nonempty and fit on one line")
    with credential_lock(home):
        _, _, provider = selected_provider(home)
        if credential_key_name(home, provider) != name:
            fail("credential settings changed; retry set-key")
        if managed_key_name(home, provider):
            reject_legacy_dotenv(home)
        path = credential_path(home, provider)
        if path.is_symlink() or path.exists() and not path.is_file():
            fail(f"refusing to replace a symlinked or nonregular credential file: {path}")
        encoded = secret.replace("\\", "\\\\").replace('"', '\\"').replace("$", "\\$").replace("`", "\\`")
        staged = None
        try:
            with tempfile.NamedTemporaryFile(mode="w", encoding="utf-8", dir=path.parent,
                                             prefix=".api-key.codex-home.", delete=False) as handle:
                staged = Path(handle.name)
                handle.write(f'{name}="{encoded}"\n')
            staged.chmod(0o600)
            os.replace(staged, path)
        finally:
            if staged is not None:
                staged.unlink(missing_ok=True)
        return str(path)


def migration_config(home: str, identity: str, kind: str) -> tuple[bytes, bytes, str]:
    """Change only one recognized legacy assignment, preserving other source bytes."""
    path = Path(home) / "config.toml"
    if path.is_symlink() or not path.is_file():
        fail("refusing to migrate a symlinked or nonregular config")
    original = path.read_bytes()
    config, selected, provider = selected_provider(home)
    labels = {"api-key": f"Codex identity: {identity}",
              "umgpt-openai": f"U-M GPT Toolkit ({identity})",
              "umgpt-low": f"U-M GPT Toolkit ({identity}; LOW-SENSITIVITY DATA ONLY)"}
    if kind not in labels or selected != identity:
        fail("refusing to migrate an identity without its named helper-generated provider")
    managed = managed_key_name(home, provider)
    if managed:
        return original, original, managed
    required = {"name", "base_url", "env_key", "wire_api"}
    if not required <= provider.keys() or provider.keys() - required - {"query_params"}:
        fail("refusing to migrate custom or ambiguous provider settings")
    if provider["name"] != labels[kind] or provider["wire_api"] != "responses":
        fail("refusing to migrate a provider that does not match the helper-generated shape")
    query = provider.get("query_params", {})
    if not isinstance(query, dict) or query.keys() - {"api-version"} or any(not isinstance(value, str) for value in query.values()):
        fail("refusing to migrate custom provider query parameters")
    name = key_name(provider["env_key"])
    lines = original.decode("utf-8").splitlines(keepends=True)
    heading = f"[model_providers.{identity}]"
    starts = [index for index, line in enumerate(lines) if line.rstrip("\r\n") == heading]
    if len(starts) != 1:
        fail("refusing to migrate a provider without one explicit generated table")
    start = starts[0] + 1
    end = next((index for index in range(start, len(lines)) if lines[index].lstrip().startswith("[")), len(lines))
    assignments = []
    for index in range(start, end):
        line = lines[index]
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if '"""' in line or "'''" in line or not re.match(r"[ \t]*(name|base_url|env_key|query_params|wire_api)[ \t]*=", line):
            fail("refusing to migrate multiline or non-generated provider assignments")
        match = re.fullmatch(r"([ \t]*)env_key[ \t]*=[ \t]*([\"'])([A-Za-z_][A-Za-z0-9_]*)\2[ \t]*(#.*)?(?:\r?\n)?", line)
        if match:
            assignments.append((index, match))
    if len(assignments) != 1 or assignments[0][1][3] != name:
        fail("refusing to migrate an ambiguous env_key assignment")
    index, match = assignments[0]
    ending = "\r\n" if lines[index].endswith("\r\n") else "\n" if lines[index].endswith("\n") else ""
    comment = " " + match[4] if match[4] else ""
    lines[index] = f"{match[1]}auth = {auth_toml(home, name)}{comment}{ending}"
    candidate = "".join(lines)
    expected = tomllib.loads(original.decode("utf-8"))
    del expected["model_providers"][identity]["env_key"]
    expected["model_providers"][identity]["auth"] = managed_auth(home, name)
    if tomllib.loads(candidate) != expected:
        fail("refusing to migrate because unrelated settings would change")
    return original, candidate.encode("utf-8"), name


def migrate_api_auth(home: str, identity: str, kind: str) -> str:
    """Move a legacy key and update its config, retaining original inodes on failure."""
    with credential_lock(home):
        original, candidate, name = migration_config(home, identity, kind)
        config = Path(home) / "config.toml"
        legacy = Path(home) / ".env"
        key = Path(home) / "api-key.env"
        for path in (legacy, key):
            if path.is_symlink() or path.exists() and not path.is_file():
                fail(f"refusing a symlinked or nonregular credential file: {path}")
        if key.exists():
            if legacy.exists() or original != candidate:
                fail("both or conflicting credential files exist; inspect .env and api-key.env before migration")
            return "already"
        if not legacy.exists() and original == candidate:
            return "already"
        if legacy.exists():
            read_secret(legacy, name)  # Validate literal data before moving it.
        recovery = Path(tempfile.mkdtemp(prefix=".api-auth-migration.", dir=home))
        config_before = recovery / "config.before"
        key_before = recovery / "key.before"
        staged = recovery / "config.new"
        config_id = config.lstat()
        config_id = (config_id.st_dev, config_id.st_ino)
        key_id = None
        candidate_id = None
        retain_recovery = False
        previous_handlers = {}

        def matches(path, expected):
            try:
                info = path.lstat()
                return (info.st_dev, info.st_ino) == expected
            except FileNotFoundError:
                return False

        def interrupted(signum, _frame):
            # Finish rollback if another cancellation arrives while restoring.
            for number in previous_handlers:
                signal.signal(number, signal.SIG_IGN)
            raise InterruptedError(f"credential migration interrupted by signal {signum}")

        try:
            os.link(config, config_before, follow_symlinks=False)
            if legacy.exists():
                os.link(legacy, key_before, follow_symlinks=False)
                info = key_before.lstat()
                key_id = (info.st_dev, info.st_ino)
            if candidate != original:
                staged.write_bytes(candidate)
                staged.chmod(0o600)
                info = staged.lstat()
                candidate_id = (info.st_dev, info.st_ino)
            for number in (signal.SIGHUP, signal.SIGINT, signal.SIGTERM):
                previous_handlers[number] = signal.signal(number, interrupted)
            if not matches(config, config_id) or config.read_bytes() != original:
                fail("refusing to migrate because config changed during preparation")
            if key_id is not None:
                # Exclusive hard links keep the key's inode, bytes, and mode.
                # An existing or concurrently inserted destination is never replaced.
                os.link(key_before, key, follow_symlinks=False)
                if not matches(legacy, key_id):
                    fail("legacy credential changed during preparation")
                legacy.unlink()
            if not matches(config, config_id) or config.read_bytes() != original:
                fail("refusing to migrate because config changed during preparation")
            if candidate_id is not None:
                os.replace(staged, config)
        except BaseException:
            # Only remove files created by this transaction. Foreign later paths
            # stay in place; original inode snapshots remain for manual recovery.
            try:
                if candidate_id is not None and matches(config, candidate_id):
                    config.unlink()
                if not config.exists() and not config.is_symlink():
                    os.link(config_before, config, follow_symlinks=False)
                if not matches(config, config_id):
                    retain_recovery = True
                if key_id is not None:
                    if not legacy.exists() and not legacy.is_symlink():
                        os.link(key_before, legacy, follow_symlinks=False)
                    if matches(legacy, key_id):
                        if matches(key, key_id):
                            key.unlink()
                    else:
                        retain_recovery = True
            except OSError:
                retain_recovery = True
            if retain_recovery:
                print(f"Credential migration recovery incomplete; originals preserved at {recovery}", file=sys.stderr)
            raise
        finally:
            for number, handler in previous_handlers.items():
                signal.signal(number, handler)
            if not retain_recovery:
                shutil.rmtree(recovery)
        return "migrated"


def read_secret(path: Path, name: str) -> str:
    if path.is_symlink() or not path.is_file():
        fail(f"refusing a symlinked or nonregular credential file: {path}")
    lines = [line for line in path.read_text().splitlines() if line.strip() and not line.lstrip().startswith("#")]
    if len(lines) != 1 or not lines[0].startswith(name + "="):
        fail(f"credential file must contain only {name}=VALUE; recreate it with set-key")
    value = lines[0][len(name) + 1:]
    if value.startswith('"') and value.endswith('"') and len(value) >= 2:
        value = value[1:-1]
        decoded = []
        index = 0
        while index < len(value):
            char = value[index]
            if char == "\\":
                index += 1
                if index >= len(value) or value[index] not in '\\"$`':
                    fail("unsupported credential escape; recreate the file with set-key")
                char = value[index]
            elif char in '"$`':
                fail("credential files contain data, not shell expressions; use set-key")
            decoded.append(char)
            index += 1
        value = "".join(decoded)
    elif value.startswith("'") and value.endswith("'") and "'" not in value[1:-1]:
        value = value[1:-1]
    elif not re.fullmatch(r"[A-Za-z0-9_./:@%+=,-]+", value):
        fail("unsupported credential syntax; recreate the file with set-key")
    if not value or any(ord(char) < 32 or ord(char) == 127 for char in value):
        fail("API key must be nonempty and fit on one line")
    return value


SAFE_ENV = {
    "HOME", "PATH", "USER", "LOGNAME", "SHELL", "LANG", "LANGUAGE", "TERM", "COLORTERM",
    "TERM_PROGRAM", "TERM_PROGRAM_VERSION", "TMPDIR", "TMP", "TEMP",
    "XDG_CACHE_HOME", "XDG_CONFIG_HOME", "XDG_DATA_HOME", "XDG_RUNTIME_DIR",
    "DISPLAY", "WAYLAND_DISPLAY", "XAUTHORITY", "DBUS_SESSION_BUS_ADDRESS",
    "NVM_DIR", "NVM_BIN", "NVM_INC", "HOMEBREW_PREFIX", "HOMEBREW_CELLAR", "HOMEBREW_REPOSITORY",
    "UV_CACHE_DIR", "UV_PYTHON_INSTALL_DIR", "VIRTUAL_ENV", "CONDA_PREFIX",
    "CODEX_HOMES_ROOT", "CODEX_UMGPT_MODELS_FILE", "CODEX_SKILLS_SOURCE",
    "CODEX_VSCODE_CLI", "CODEX_VSCODE_EXTENSIONS_DIR", "CODEX_VSCODE_DOCK_LABEL",
    "EDITOR", "VISUAL", "PAGER", "__CF_USER_TEXT_ENCODING", "SECURITYSESSIONID",
}


def blocked_variable(name: str) -> bool:
    return name.startswith(("LD_", "DYLD_")) or name in {
        "BASH_ENV", "ENV", "SHELLOPTS", "BASHOPTS", "CDPATH", "GLOBIGNORE", "IFS",
        "PYTHONPATH", "PYTHONHOME", "PYTHONSTARTUP", "NODE_OPTIONS", "NODE_PATH",
        "RUBYOPT", "PERL5OPT", "PERL5LIB", "CODEX_HOME", "CODEX_IDENTITY",
    }


def extra_environment() -> set[str]:
    extra = set(os.environ.get("CODEX_CONTEXTS_ENV_ALLOW", "").split())
    for name in extra:
        if not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*", name) or blocked_variable(name):
            fail(f"unsafe CODEX_CONTEXTS_ENV_ALLOW variable: {name}")
    return extra


def selected_secret(home: str | Path, name: str) -> str:
    path = Path(home) / ".env"
    if path.exists() or path.is_symlink():
        return read_secret(path, name)
    if name in extra_environment() and os.environ.get(name):
        return os.environ[name]
    fail(f"missing selected key {name}; run set-key or explicitly include {name} in CODEX_CONTEXTS_ENV_ALLOW")


def file_secret(home: str | Path, name: str) -> str:
    reject_legacy_dotenv(home)
    path = Path(home) / "api-key.env"
    if not path.exists() and not path.is_symlink():
        fail(f"missing selected key {name}; run set-key")
    return read_secret(path, name)


def clean_environment() -> dict[str, str]:
    extra = extra_environment()
    environment = {
        name: value for name, value in os.environ.items()
        if name in SAFE_ENV or name.startswith("LC_") or name in extra
    }
    if extra:
        environment["CODEX_CONTEXTS_ENV_ALLOW"] = " ".join(sorted(extra))
    return environment


def launch(identity: str, home: str, command: list[str], with_key: bool = True) -> None:
    environment = clean_environment()
    environment.update(CODEX_HOME=home, CODEX_IDENTITY=identity)
    if with_key:
        _, _, provider = selected_provider(home)
        managed = managed_key_name(home, provider)
        if managed:
            file_secret(home, managed)  # Fail before starting the application.
            environment.pop(managed, None)
        else:
            name = credential_key_name(home, provider)
            if name:
                environment[name] = selected_secret(home, name)
    if not command:
        fail("missing launch command")
    os.execvpe(command[0], command, environment)


def validate_project(path: str, scope: str) -> None:
    config = read_config(path)
    # Inspect parsed keys so quoted, escaped, dotted, and inline spellings all
    # have the same meaning. A project may tune models, never provider routing.
    for key in ("model_provider", "model_providers", "openai_base_url", "chatgpt_base_url", "profile"):
        if key in config:
            fail(f"project config may not override the provider for U-M GPT identities: {path}")
    if scope == "openai-only" and "model_catalog_json" in config:
        fail(f"project config may not install a custom model catalog for the U-M GPT Azure OpenAI identity: {path}")
    features = config.get("features", {})
    if not isinstance(features, dict):
        fail(f"project features must be a table: {path}")
    if scope == "openai-only" and any(features.get(key) for key in ("api_key_model_discovery", "remote_models")):
        fail(f"project config may not enable unfiltered model discovery: {path}")
    def models(table: dict) -> None:
        for key, value in table.items():
            if key in {"model_provider", "model_providers", "openai_base_url", "chatgpt_base_url", "profile"}:
                fail(f"project config may not override the provider for U-M GPT identities: {path}")
            if key == "model":
                if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/@+\-]*", value):
                    fail(f"invalid project model: {path}")
                if any(part in value.lower() for part in ("image", "embedding")):
                    fail(f"project model is not a general Codex text model: {path}")
                if scope == "openai-only" and not re.match(r"^(gpt-|o[0-9])", value):
                    fail(f"U-M GPT Azure OpenAI identities require a GPT or o-series text model: {path}")
            elif isinstance(value, dict):
                models(value)
    models(config)


def validate_umgpt_identity(home: str, identity: str, scope: str) -> None:
    config, provider_name, provider = selected_provider(home)
    if provider_name != identity or provider.get("base_url", "").rstrip("/") != "https://api.toolkit.umgpt.umich.edu/v1":
        fail("U-M GPT identity must use its named provider at the U-M GPT gateway")
    if credential_key_name(home, provider) != "UMGPT_API_KEY":
        fail("U-M GPT identity must use UMGPT_API_KEY")
    if "model_catalog_url" in provider:
        fail("U-M GPT identity may not override its model catalog URL; use refresh-models for a scope-filtered catalog")
    if "profile" in config:
        fail("U-M GPT identities may not select a default profile; use a separate identity")
    model = config.get("model", "")
    if not isinstance(model, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/@+\-]*", model):
        fail("invalid U-M GPT model ID")
    if any(part in model.lower() for part in ("image", "embedding")):
        fail("U-M GPT identity requires a general text model")
    if scope == "openai-only" and not re.match(r"^(gpt-|o[0-9])", model):
        fail("U-M GPT Azure OpenAI identity requires a GPT or o-series text model")


def validate_config_urls(config: dict) -> None:
    """Check endpoint fields without interpreting unrelated native settings."""
    for field in ("openai_base_url", "chatgpt_base_url"):
        if field in config:
            validate_url(config[field], field=field)
    providers = config.get("model_providers", {})
    if not isinstance(providers, dict):
        fail("model_providers must be a TOML table")
    for name, provider in providers.items():
        if not isinstance(provider, dict):
            fail(f"model_providers.{name!r} must be a TOML table")
        for field in ("base_url", "model_catalog_url"):
            if field in provider:
                # A catalog URL is a complete request URL. Its query can carry
                # API versions or filters; base URLs are joined with API paths.
                validate_url(provider[field], field=f"model_providers.{name!r}.{field}",
                             allow_query=field == "model_catalog_url")
    profiles = config.get("profiles", {})
    if not isinstance(profiles, dict):
        fail("profiles must be a TOML table")
    for name, profile in profiles.items():
        if not isinstance(profile, dict):
            fail(f"profiles.{name!r} must be a TOML table")
        validate_config_urls(profile)


def parse_override(override: str) -> dict:
    if "=" not in override or "\n" in override or "\r" in override:
        fail("config override must be a single key=value assignment")
    try:
        return tomllib.loads(override)
    except tomllib.TOMLDecodeError:
        # Native CLI accepts an unquoted RHS as a literal string when TOML
        # parsing fails. Still parse the key with TOML to resolve escaped keys.
        key, value = override.split("=", 1)
        result = tomllib.loads(key + '= "placeholder"')
        leaf = result
        while isinstance(next(iter(leaf.values())), dict):
            leaf = next(iter(leaf.values()))
        leaf[next(iter(leaf))] = value.strip()
        return result


def launch_check(home: str, args: list[str]) -> None:
    config, _, _ = selected_provider(home)
    project = Path.cwd()
    profiles = []
    if isinstance(config.get("profile"), str):
        profiles.append(config["profile"])
    index = 0
    while index < len(args):
        arg = args[index]
        if arg == "--":
            break
        value = None
        if arg in {"-C", "--cd", "-p", "--profile", "-c", "--config"}:
            index += 1
            if index >= len(args):
                fail(f"{arg} requires a value")
            value = args[index]
        elif arg.startswith(("--cd=", "--profile=", "--config=")):
            arg, value = arg.split("=", 1)
        elif len(arg) > 2 and arg[:2] in {"-C", "-p", "-c"}:
            arg, value = arg[:2], arg[2:]
        if value is not None:
            if arg in {"-C", "--cd"}:
                project = Path(value)
            elif arg in {"-p", "--profile"}:
                profiles.append(value)
            else:
                override = parse_override(value)
                validate_config_urls(override)
                if isinstance(override.get("profile"), str):
                    profiles.append(override["profile"])
        index += 1
    project = project.resolve(strict=True)
    if not project.is_dir():
        fail("project root must be a directory")
    for directory in (project, *project.parents):
        path = directory / ".codex" / "config.toml"
        if path.exists():
            project_config = read_config(path)
            validate_config_urls(project_config)
            if isinstance(project_config.get("profile"), str):
                profiles.append(project_config["profile"])
    for profile in profiles:
        path = Path(home) / (profile + ".config.toml")
        if path.exists():
            validate_config_urls(read_config(path))


def validate_override(scope: str, override: str) -> None:
    # Codex accepts unquoted strings on CLI. Parse the key independently while
    # requiring a single assignment; quoted/escaped/dotted keys stay meaningful.
    if "=" not in override or "\n" in override or "\r" in override:
        fail("config override must be a single key=value assignment")
    key = override.split("=", 1)[0]
    data = tomllib.loads(key + '= "placeholder"')
    forbidden = {"model", "model_provider", "model_providers", "model_catalog_json", "openai_base_url", "chatgpt_base_url", "profile"}
    if forbidden.intersection(data):
        fail("config override can bypass the U-M GPT model/provider scope")
    if scope == "openai-only" and "features" in data:
        if not isinstance(data["features"], dict) or {
            "api_key_model_discovery", "remote_models"
        }.intersection(data["features"]):
            fail("config override can bypass the U-M GPT model scope")


def main() -> None:
    action, *args = sys.argv[1:]
    if action == "url":
        validate_url(args[0])
    elif action == "key-name":
        print(selected_key_name(args[0]))
    elif action == "auth-config":
        print(auth_toml(args[0], args[1]))
    elif action == "credential-path":
        _, _, provider = selected_provider(args[0])
        if managed_key_name(args[0], provider):
            reject_legacy_dotenv(args[0])
        print(credential_path(args[0], provider))
    elif action == "store-key":
        print(store_key(args[0], key_name(args[1]), sys.stdin.read()))
    elif action == "credential":
        if not Path(args[0]).is_absolute():
            fail("credential home must be absolute")
        print(file_secret(args[0], key_name(args[1])), end="")
    elif action == "migrate-api-auth":
        print(migrate_api_auth(args[0], args[1], args[2]))
    elif action == "provider-value":
        _, _, provider = selected_provider(args[0])
        value = provider.get(args[1], "")
        if not isinstance(value, str):
            fail("provider field must be a string")
        print(value)
    elif action == "root-value":
        value = read_config(Path(args[0]) / "config.toml").get(args[1], "")
        if not isinstance(value, str):
            fail("root config field must be a string")
        print(value)
    elif action == "config-file":
        read_config(args[0])
    elif action == "validate-key-name":
        key_name(args[0])
    elif action == "secret":
        _, _, provider = selected_provider(args[0])
        name = credential_key_name(args[0], provider)
        if name:
            secret = file_secret(args[0], name) if managed_key_name(args[0], provider) else selected_secret(args[0], name)
            print(secret, end="")
    elif action == "launch":
        launch(args[0], args[1], args[2:])
    elif action == "review":
        launch(args[0], args[1], args[2:], with_key=False)
    elif action == "client":
        os.execvpe(args[0], args, clean_environment())
    elif action == "fingerprint":
        digest = hashlib.sha256()
        for index, value in enumerate(args):
            path = Path(value)
            digest.update(str(path).encode() + b"\0")
            if index:
                if path.is_symlink() or not path.is_file():
                    fail("project fingerprint requires regular generated files")
                data = path.read_bytes()
                digest.update(len(data).to_bytes(8, "big") + data)
        print(digest.hexdigest())
    elif action == "project":
        validate_project(args[0], args[1])
    elif action == "identity":
        selected_provider(args[0])
    elif action == "umgpt-identity":
        validate_umgpt_identity(args[0], args[1], args[2])
    elif action == "override":
        validate_override(args[0], args[1])
    elif action == "launch-check":
        launch_check(args[0], args[1:])
    else:
        fail("unknown data-helper action")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, TypeError, KeyError, IndexError) as error:
        print(f"codex-home: {error}", file=sys.stderr)
        raise SystemExit(1)
