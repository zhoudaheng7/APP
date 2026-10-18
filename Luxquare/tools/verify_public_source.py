"""Refuse accidental inclusion of workbench server code, origins, or secrets."""
from __future__ import annotations

import argparse
import hashlib
import json
import plistlib
import re
from pathlib import Path

FOLDERS = {"Sources", "Resources", "Assets", "UITests", "Tests", "tools", ".github"}
ROOT_FILES = {"project.yml", "Info.plist", "Package.swift", "README.md", "LICENSE"}
IGNORED = {".git", "build", "dist", "Luxquare.xcodeproj", "__pycache__", ".pytest_cache", ".DS_Store"}
FORBIDDEN_NAMES = {".env", "remote81.py", "framework_remote_operator.py", "module_control.py", "sso.py", "AGENTS.md", "STATE.md"}
SECRET_SUFFIXES = {".p12", ".mobileprovision", ".pem", ".key", ".dump", ".sqlite", ".db", ".ipa"}
PATTERNS = [
    ("private-key", re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----")),
    ("github-token", re.compile(r"(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{30,})")),
    ("server-origin", re.compile("(?:" + "ac51" + "64f7" + r"|\.nip\.io|\.sslip\.io)", re.I)),
    ("server-address", re.compile(r"\b(?:\d{1,3}\.){3}\d{1,3}\b")),
    ("local-owner-path", re.compile(r"(?:C:[/\\]Users[/\\]Flare|D:[/\\]appstore)", re.I)),
]


def inspect(root: Path) -> dict:
    root = root.resolve()
    checked = []
    violations = []
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if any(part in IGNORED for part in relative.parts):
            continue
        if path.is_symlink():
            violations.append({"path": relative.as_posix(), "reason": "symbolic-link"})
            continue
        if not path.is_file():
            continue
        if (len(relative.parts) == 1 and path.name not in ROOT_FILES) or (len(relative.parts) > 1 and relative.parts[0] not in FOLDERS):
            violations.append({"path": relative.as_posix(), "reason": "outside-client-allowlist"})
            continue
        if path.name in FORBIDDEN_NAMES or path.suffix.lower() in SECRET_SUFFIXES:
            violations.append({"path": relative.as_posix(), "reason": "private-material-name"})
            continue
        data = path.read_bytes()
        if path.suffix.lower() == ".plist":
            obj = plistlib.loads(data)
            if obj.get("LuxquareBaseURL") or obj.get("LuxquareUpdateURL"):
                violations.append({"path": relative.as_posix(), "reason": "origin-must-be-injected-locally"})
        if path.suffix.lower() not in {".png", ".jpg", ".jpeg", ".heic", ".pdf"}:
            text = data.decode("utf-8")
            for reason, pattern in PATTERNS:
                if pattern.search(text):
                    violations.append({"path": relative.as_posix(), "reason": reason})
        checked.append({"path": relative.as_posix(), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    return {"schema": "lux-public-client-scan/v1", "allowed": not violations, "files": checked, "violations": violations}


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("root", type=Path)
    parser.add_argument("--report", type=Path)
    args = parser.parse_args()
    result = inspect(args.root)
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"allowed": result["allowed"], "checked": len(result["files"]), "violations": result["violations"]}))
    raise SystemExit(0 if result["allowed"] else 1)
