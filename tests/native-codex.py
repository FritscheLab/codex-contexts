#!/usr/bin/env python3
"""Check real Codex against generated config, local auth, and a loopback model fixture."""

import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import queue
import shlex
import shutil
import subprocess
import sys
import tempfile
import threading
import time
from contextlib import contextmanager


REPO = Path(__file__).resolve().parent.parent
TOOL = REPO / "bin/codex-home"


def completed(response_id):
    return {"type": "response.completed", "response": {"id": response_id}}


@contextmanager
def responses_fixture(scenarios):
    """Serve exactly one streamed tool call and one final response per identity."""
    failures = []

    class Handler(BaseHTTPRequestHandler):
        def log_message(self, *_arguments):
            pass

        def do_POST(self):
            try:
                self.connection.settimeout(10)
                assert self.client_address[0] == "127.0.0.1", "non-loopback client"
                scenario = scenarios[self.path]
                assert self.headers.get("Authorization") == f"Bearer {scenario['key']}", "wrong identity key"
                size = int(self.headers.get("Content-Length", "0"))
                assert 0 < size < 8_000_000, "unexpected request size"
                request = json.loads(self.rfile.read(size))
                assert request["model"] == "synthetic-model" and request["stream"], "wrong model or transport"
                scenario["requests"] += 1
                assert scenario["requests"] <= 2, "unexpected retry or extra model request"
                if scenario["requests"] == 1:
                    names = {tool.get("name") for tool in request["tools"]}
                    name = "exec_command" if "exec_command" in names else "shell_command"
                    assert name in names, f"no native shell tool offered: {sorted(str(n) for n in names)}"
                    arguments = {"cmd" if name == "exec_command" else "command": scenario["command"], "login": False}
                    if name == "exec_command":
                        arguments.update(shell="/bin/sh", yield_time_ms=1000)
                    call = {"type": "function_call", "id": "fc_probe", "call_id": "contract_probe",
                            "name": name, "arguments": json.dumps(arguments)}
                    events = [{"type": "response.created", "response": {"id": "resp_probe"}},
                              {"type": "response.output_item.done", "item": call}, completed("resp_probe")]
                else:
                    outputs = [item for item in request["input"]
                               if item.get("type") == "function_call_output" and item.get("call_id") == "contract_probe"]
                    assert len(outputs) == 1, "missing actual tool result"
                    output = outputs[0]["output"]
                    if isinstance(output, list):
                        output = "\n".join(item.get("text", "") for item in output)
                    marker = "CONTRACT_PROBE "
                    assert marker in output, "native shell probe did not complete"
                    scenario["probe"] = json.JSONDecoder().raw_decode(output.split(marker, 1)[1])[0]
                    message = {"type": "message", "role": "assistant", "id": "msg_done",
                               "content": [{"type": "output_text", "text": "LOCAL_CONTRACT_COMPLETE"}]}
                    events = [{"type": "response.created", "response": {"id": "resp_done"}},
                              {"type": "response.output_item.done", "item": message}, completed("resp_done")]
                self.send_response(200)
                self.send_header("Content-Type", "text/event-stream")
                self.send_header("Connection", "close")
                self.end_headers()
                for event in events:
                    self.wfile.write(f"event: {event['type']}\ndata: {json.dumps(event)}\n\n".encode())
                    self.wfile.flush()
            except (AssertionError, KeyError, ValueError, OSError) as error:
                failures.append(f"{self.path}: {error}")
                self.send_error(500, "local contract assertion failed")

    server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
    server.daemon_threads = True
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield server.server_port, failures
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)


def tool_roundtrips(helper, root, homes, project, environment):
    scenarios = {}
    outside = root / "outside"
    outside.mkdir()
    with responses_fixture(scenarios) as (port, failures):
        for mode in ("workspace-write", "read-only"):
            identity = f"tool-{mode}"
            key = f"synthetic-{identity}-key"
            helper("create-api", identity, f"http://127.0.0.1:{port}/{identity}/v1", "synthetic-model", "CONTRACT_TOOL_KEY")
            helper("set-sandbox", identity, mode)
            home = homes / identity
            config = home / "config.toml"
            secret = home / "api-key.env"
            if mode == "read-only":
                # Exercise legacy migration against native dotenv startup too:
                # retaining this old file would re-export the selected key.
                config.write_text("\n".join(
                    'env_key = "CONTRACT_TOOL_KEY"' if line.startswith("auth = ") else line
                    for line in config.read_text().splitlines()) + "\n")
                (home / ".env").write_text(f'CONTRACT_TOOL_KEY="{key}"\n')
                helper("migrate-api-auth", identity)
                assert not (home / ".env").exists(), "migration retained native dotenv key exposure"
                assert secret.read_text() == f'CONTRACT_TOOL_KEY="{key}"\n', "migration changed the stored key"
            else:
                secret.write_text(f'CONTRACT_TOOL_KEY="{key}"\n')
                secret.chmod(0o600)
            config.write_text(config.read_text().replace(f"[model_providers.{identity}]",
                              f"[model_providers.{identity}]\nrequest_max_retries = 0\nstream_max_retries = 0") +
                              '\n[analytics]\nenabled = false\n[features]\napi_key_model_discovery = false\nremote_models = false\n'
                              '[sandbox_workspace_write]\nexclude_tmpdir_env_var = true\nexclude_slash_tmp = true\n')
            workspace_file = project / f"{identity}.txt"
            outside_file = outside / f"{identity}.txt"
            # Both paths are writable without the command sandbox; a denial
            # must come from the selected native policy, not fixture ownership.
            for path in (workspace_file, outside_file):
                path.write_text("fixture write check")
                path.unlink()
            probe = (
                "import json,os; from pathlib import Path\n"
                "def write(path):\n"
                " try: Path(path).write_text('synthetic probe'); return True\n"
                " except OSError: return False\n"
                f"result={{'cwd':os.getcwd(),'home':os.environ.get('CODEX_HOME'),'identity':os.environ.get('CODEX_IDENTITY'),"
                "'unrelated_key':bool(os.environ.get('UNRELATED_API_KEY')),'selected_key':bool(os.environ.get('CONTRACT_TOOL_KEY')),"
                f"'workspace_write':write({str(workspace_file)!r}),'outside_write':write({str(outside_file)!r})}}\n"
                "print('CONTRACT_PROBE '+json.dumps(result))"
            )
            scenario = {"key": key, "command": shlex.join([sys.executable, "-I", "-c", probe]), "requests": 0}
            scenarios[f"/{identity}/v1/responses"] = scenario
            run_environment = {**environment, "SHELL": "/bin/sh", "UNRELATED_API_KEY": "synthetic-unrelated-key"}
            result = subprocess.run([str(TOOL), "run", identity, "--no-daemon", "--ask-for-approval", "never",
                                     "exec", "--json", "--ephemeral", "--skip-git-repo-check", "Run the local contract probe."],
                                    cwd=project, env=run_environment, text=True, capture_output=True, timeout=60)
            assert not failures, failures
            assert result.returncode == 0, result.stderr[-3000:]
            assert "LOCAL_CONTRACT_COMPLETE" in result.stdout, "final streamed response missing"
            assert scenario["requests"] == 2, "tool roundtrip did not make exactly two model requests"
            observed = scenario["probe"]
            assert observed["cwd"] == str(project) and observed["home"] == str(home) and observed["identity"] == identity, observed
            assert not observed["unrelated_key"], "unrelated credential reached generated command"
            assert observed["workspace_write"] == (mode == "workspace-write") == workspace_file.exists(), observed
            assert not observed["outside_write"] and not outside_file.exists(), observed
            assert not observed["selected_key"], "managed API key reached generated command environment"
            print(f"Native tool roundtrip passed ({mode}; identity and credential isolation verified).")


def read_native(identity, project, environment):
    """Only initialize, read config, and read local auth without token refresh."""
    with tempfile.TemporaryFile(mode="w+t") as errors:
        process = subprocess.Popen(
            [str(TOOL), "run", identity, "--strict-config", "app-server", "--listen", "stdio://"],
            cwd=project, env=environment, text=True,
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=errors,
        )
        replies = queue.Queue()

        def read_replies():
            try:
                for line in process.stdout:
                    replies.put(json.loads(line))
            finally:
                replies.put(None)

        reader = threading.Thread(target=read_replies, daemon=True)
        reader.start()

        def send(message):
            process.stdin.write(json.dumps(message) + "\n")
            process.stdin.flush()

        def request(number, method, params):
            send({"id": number, "method": method, "params": params})
            deadline = time.monotonic() + 30
            while True:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise RuntimeError(f"{method}: timed out waiting for native Codex")
                reply = replies.get(timeout=remaining)
                if reply is None:
                    raise RuntimeError("native Codex exited before replying")
                if reply.get("id") == number:
                    if "error" in reply:
                        raise RuntimeError(f"{method}: {reply['error']}")
                    return reply["result"]

        try:
            request(1, "initialize", {
                "clientInfo": {"name": "codex-contexts-test", "version": "1.0"},
                "capabilities": {"experimentalApi": True},
            })
            send({"method": "initialized", "params": {}})
            config = request(2, "config/read", {"cwd": str(project), "includeLayers": True})
            account = request(3, "account/read", {"refreshToken": False})
            return config["config"], account["account"]
        except (BrokenPipeError, queue.Empty, RuntimeError):
            errors.seek(0)
            print(errors.read())
            raise
        finally:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=5)
            reader.join(timeout=5)
            process.stdin.close()
            process.stdout.close()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--codex", type=Path, help="test this runtime, independently of the CI version pin")
    options = parser.parse_args()
    codex = str(options.codex.resolve()) if options.codex else shutil.which("codex")
    if not codex:
        raise SystemExit("Install the pinned Codex CLI from the CI workflow first.")
    # Do not forward real credentials, config selection, proxies, or loader flags.
    environment = {"HOME": os.environ["HOME"], "PATH": os.environ["PATH"], "LANG": "C.UTF-8"}
    with tempfile.TemporaryDirectory(prefix="codex-native-contract.") as temporary:
        root = Path(temporary).resolve()
        homes = root / "homes"
        project = root / "project"
        project.mkdir()
        shim_directory = root / "bin"
        shim_directory.mkdir()
        shim = shim_directory / "codex"
        shim.write_text(f'#!/bin/sh\nexec {shlex.quote(codex)} "$@"\n')
        shim.chmod(0o700)
        environment["PATH"] = f"{shim_directory}{os.pathsep}{environment['PATH']}"
        environment.update(CODEX_HOME=str(root), CODEX_HOMES_ROOT=str(homes),
                           CODEX_UMGPT_MODELS_FILE=str(root / "model-settings.toml"))
        version = subprocess.check_output([codex, "--version"], env=environment, text=True).strip()
        expected = None if options.codex else os.environ.get("CODEX_CONTRACT_VERSION")
        if expected and version != f"codex-cli {expected}":
            raise AssertionError(f"Expected Codex {expected}; got {version}")

        def helper(*arguments):
            subprocess.run([str(TOOL), *arguments], cwd=project, env=environment,
                           check=True, capture_output=True, text=True, timeout=30)

        helper("create-subscription", "signed-out")
        helper("create-subscription", "local-auth")
        helper("create-api", "api", "https://api.example.test/v1", "synthetic-model", "CONTRACT_API_KEY")
        helper("create-azure", "azure", "https://azure.example.test/openai", "synthetic-deployment",
               "CONTRACT_AZURE_KEY", "2025-04-01-preview")
        helper("create-umgpt", "gpt-4.1", "campus")

        for identity in ("signed-out", "local-auth", "api", "azure", "campus"):
            home = homes / identity
            config_path = home / "config.toml"
            text = config_path.read_text()
            if identity not in ("signed-out", "local-auth"):
                text = 'cli_auth_credentials_store = "file"\n' + text
            # Disable optional background discovery/analytics. No turn is started.
            text += '\n[analytics]\nenabled = false\n[features]\napi_key_model_discovery = false\nremote_models = false\n'
            config_path.write_text(text)
        (homes / "local-auth/auth.json").write_text(json.dumps({"OPENAI_API_KEY": "synthetic-local-auth"}))
        for identity, key in (("api", "CONTRACT_API_KEY"), ("azure", "CONTRACT_AZURE_KEY"), ("campus", "UMGPT_API_KEY")):
            secret = homes / identity / "api-key.env"
            secret.write_text(f'{key}="synthetic-provider-key"\n')
            secret.chmod(0o600)

        helper("set-sandbox", "signed-out", "read-only")
        helper("set-sandbox", "api", "workspace-write")
        api_config = homes / "api/config.toml"
        api_config.write_text('chatgpt_base_url = "https://chat.example.test"\n' + api_config.read_text())
        # Native catalog URLs are request URLs and may carry a query string.
        with api_config.open("a") as handle:
            handle.write('\n[model_providers.catalog-only]\nname = "Catalog contract"\n'
                         'model_catalog_url = "https://catalog.example.test/models?channel=test"\n')

        configs = {}
        accounts = {}
        for identity in ("signed-out", "local-auth", "api", "azure", "campus"):
            configs[identity], accounts[identity] = read_native(identity, project, environment)
        assert accounts["signed-out"] is None
        assert accounts["local-auth"] == {"type": "apiKey"}
        assert configs["signed-out"]["cli_auth_credentials_store"] == "file"
        assert configs["signed-out"]["sandbox_mode"] == "read-only"
        assert configs["api"]["sandbox_mode"] == "workspace-write"
        assert configs["api"]["approval_policy"] == "on-request"
        assert configs["api"]["approvals_reviewer"] == "user"
        assert configs["api"]["chatgpt_base_url"] == "https://chat.example.test"
        assert configs["api"]["model_providers"]["catalog-only"]["model_catalog_url"].endswith("?channel=test")
        for identity in ("api", "azure", "campus"):
            config = configs[identity]
            assert config["model_provider"] == identity
            assert config["model_providers"][identity]["wire_api"] == "responses"
        assert configs["azure"]["model_providers"]["azure"]["query_params"] == {"api-version": "2025-04-01-preview"}
        for identity, key in (("api", "CONTRACT_API_KEY"), ("azure", "CONTRACT_AZURE_KEY"), ("campus", "UMGPT_API_KEY")):
            provider = configs[identity]["model_providers"][identity]
            assert provider.get("env_key") is None
            assert provider["auth"]["args"][-2:] == [str(homes / identity), key]
        # Read the empty home again after the authenticated one: auth must stay separate.
        assert read_native("signed-out", project, environment)[1] is None
        tool_roundtrips(helper, root, homes, project, environment)
        print(f"Native contracts passed ({version}; generated config, local auth, loopback tool use and sandbox enforcement).")


if __name__ == "__main__":
    main()
