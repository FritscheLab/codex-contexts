#!/usr/bin/env python3
"""Filesystem boundaries shared by the macOS bundle commands."""
from __future__ import annotations

import ctypes
import fcntl
import hashlib
import os
from pathlib import Path
import plistlib
import re
import stat
import sys
import time


def identity(path: str | Path) -> str:
    info = os.lstat(path)
    return f"{info.st_dev}:{info.st_ino}"


def lock_files(arguments: list[str]) -> None:
    timeout = None
    if arguments[:1] == ["--timeout"]:
        timeout = float(arguments[1])
        if not 0 <= timeout < float("inf"):
            raise ValueError("lock timeout must be finite and nonnegative")
        arguments = arguments[2:]
    if not arguments or len(arguments) % 2:
        raise ValueError("lock requires descriptor/path pairs")
    locks = {}
    for index in range(0, len(arguments), 2):
        fd, path = int(arguments[index]), arguments[index + 1]
        opened, named = os.fstat(fd), os.lstat(path)
        parent = os.stat(os.path.dirname(path))
        key = (opened.st_dev, opened.st_ino)
        if (not stat.S_ISREG(opened.st_mode) or opened.st_uid != os.getuid()
                or opened.st_nlink != 1 or opened.st_mode & 0o022
                or parent.st_uid != os.getuid() or parent.st_mode & 0o022
                or key != (named.st_dev, named.st_ino)):
            raise ValueError(f"refusing an unsafe bundle lock: {path}")
        locks.setdefault(key, (fd, path))
    deadline = None if timeout is None else time.monotonic() + timeout
    # Shared directories and alternate path spellings use the same lock once.
    for key, (fd, path) in sorted(locks.items()):
        while True:
            try:
                operation = fcntl.LOCK_EX
                if deadline is not None:
                    operation |= fcntl.LOCK_NB
                fcntl.flock(fd, operation)
                break
            except BlockingIOError:
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError(f"timed out waiting for bundle lock: {path}")
                time.sleep(min(0.05, remaining))
        named = os.lstat(path)
        if key != (named.st_dev, named.st_ino):
            raise ValueError(f"bundle lock changed while waiting: {path}")


def rename_bundle(source: str, destination: str, expected: str) -> None:
    if identity(source) != expected:
        raise ValueError(f"bundle changed before moving: {source}")
    # os.rename replaces an empty destination directory. RENAME_EXCL refuses
    # every existing destination, including symlinks, and cannot nest bundles.
    rename = ctypes.CDLL(None, use_errno=True).renamex_np
    rename.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint)
    rename.restype = ctypes.c_int
    if rename(os.fsencode(source), os.fsencode(destination), 0x00000004):
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error), destination)


def regular(path: Path) -> bool:
    return stat.S_ISREG(path.lstat().st_mode)


def directory(path: Path) -> bool:
    return stat.S_ISDIR(path.lstat().st_mode)


def bundle_info(bundle: Path, *, resources: bool = False) -> dict:
    if not directory(bundle) or not directory(bundle / "Contents"):
        raise ValueError("bundle and Contents must be real directories")
    if resources and not directory(bundle / "Contents/Resources"):
        raise ValueError("Resources must be a real directory")
    path = bundle / "Contents/Info.plist"
    if not regular(path):
        raise ValueError("bundle Info.plist must be a regular file")
    with path.open("rb") as handle:
        return plistlib.load(handle)


def marker_lines(path: Path) -> list[str]:
    if not regular(path):
        raise ValueError("bundle marker must be a regular file")
    return path.read_text(encoding="utf-8").split("\n")


def handler_name(bundle: Path) -> str:
    match = re.fullmatch(r"VS Code - ([A-Za-z0-9][A-Za-z0-9_-]*)\.app", bundle.name)
    if not match:
        raise ValueError("unrecognized identity bundle name")
    return match[1]


def owned_bundle(kind: str, path: str, expected_name: str = "") -> bool:
    bundle = Path(path)
    try:
        info = bundle_info(bundle, resources=kind in {"project", "handler"})
        bundle_id = info.get("CFBundleIdentifier")
        if kind == "workflow":
            return info.get("CodexContextsManagedWorkflow") == "codex-contexts-quick-action-v1"
        if kind == "project":
            helper = bundle / "Contents/Resources/codex-home"
            return (bundle_id == "org.codex-contexts.project" and regular(helper)
                    and os.access(helper, os.X_OK))
        if kind == "handler":
            name = handler_name(bundle)
            resources = bundle / "Contents/Resources"
            marker = marker_lines(resources / "codex-contexts-open-with")
            identity_file = resources / "identity"
            helper = resources / "codex-home"
            return (not expected_name or expected_name == name) and (
                marker[:2] == ["codex-contexts-vscode-open-with-v1", name]
                and regular(identity_file)
                and identity_file.read_text(encoding="utf-8").rstrip("\n") == name
                and regular(helper) and os.access(helper, os.X_OK)
                and bundle_id == f"org.codex-contexts.vscode.{name}")
        if kind == "named-editor":
            handler_name(bundle)
            cache = bundle.parent
            return (directory(cache)
                    and marker_lines(cache / "source")[:1] == ["codex-contexts-vscode-editor-v1"]
                    and bundle_id in {"com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"})
        if kind == "legacy-editor":
            return bundle_id == f"org.codex-contexts.vscode.{handler_name(bundle)}"
        raise ValueError(f"unknown bundle kind: {kind}")
    except (OSError, ValueError, TypeError, AttributeError, plistlib.InvalidFileException):
        return False


def fingerprint(paths: list[str]) -> str:
    digest = hashlib.sha256()
    for value in paths:
        root = Path(value)
        if root.is_symlink():
            raise ValueError(f"refusing symlinked launcher resource: {root}")
        files = sorted(root.rglob("*")) if root.is_dir() else [root]
        digest.update(os.fsencode(root) + b"\0")
        for path in files:
            if path.is_symlink():
                raise ValueError(f"refusing symlinked launcher resource: {path}")
            if path.is_dir():
                continue
            if not regular(path):
                raise ValueError(f"launcher resource must be a regular file: {path}")
            data = path.read_bytes()
            digest.update(os.fsencode(path.relative_to(root) if root.is_dir() else path.name) + b"\0")
            digest.update(len(data).to_bytes(8, "big") + data)
    return digest.hexdigest()


def main() -> int:
    action, *args = sys.argv[1:]
    if action == "lock":
        lock_files(args)
    elif action == "rename":
        rename_bundle(*args)
    elif action == "identity":
        print(identity(args[0]))
    elif action == "handler-lock":
        bundle = Path(args[0])
        print(bundle.parent / f".codex-contexts-vscode-{handler_name(bundle)}.lock")
    elif action == "owned":
        if not owned_bundle(*args):
            return 1
        print(identity(args[1]))
    elif action == "fingerprint":
        print(fingerprint(args))
    else:
        raise ValueError(f"unknown macOS helper action: {action}")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (OSError, ValueError, TypeError, IndexError) as error:
        print(f"codex-contexts: {error}", file=sys.stderr)
        raise SystemExit(1)
