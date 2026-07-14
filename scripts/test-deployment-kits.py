#!/usr/bin/env python3
"""Validate that customer ZIP files contain the secure noVNC deployment path."""

from __future__ import annotations

import argparse
import zipfile
from pathlib import Path


COMMON_FILES = {
    ".env.example",
    "docker-compose.yml",
    "docker-compose.vnc.yml",
    "global_config.yml",
    "客户使用说明.txt",
}

VNC_ENV_KEYS = {
    "VNC_PASSWORD_FILE",
    "NOVNC_PORT",
    "MANUAL_VERIFICATION_URL",
    "XY_MANUAL_SLIDER_TAKEOVER_TIMEOUT",
}


def archive_files(path: Path) -> set[str]:
    with zipfile.ZipFile(path) as archive:
        names = set()
        for name in archive.namelist():
            parts = Path(name).parts
            if len(parts) >= 2:
                names.add(Path(*parts[1:]).as_posix())
        return names


def require_files(path: Path, expected: set[str]) -> None:
    names = archive_files(path)
    missing = sorted(expected - names)
    if missing:
        raise SystemExit(f"{path.name} is missing: {', '.join(missing)}")


def validate_installer_sources(repository_root: Path) -> None:
    macos_source = (repository_root / "scripts/lazyfish-macos.sh").read_text(
        encoding="utf-8"
    )
    if "migrate_vnc_env_defaults" not in macos_source:
        raise SystemExit("macOS installer is missing legacy .env migration")
    for key in VNC_ENV_KEYS:
        if key not in macos_source:
            raise SystemExit(f"macOS installer is missing {key}")

    windows_path = repository_root / "scripts/lazyfish-windows.ps1"
    windows_bytes = windows_path.read_bytes()
    if not windows_bytes.startswith(b"\xef\xbb\xbf"):
        raise SystemExit("Windows installer must retain its UTF-8 BOM")
    windows_source = windows_bytes.decode("utf-8-sig")
    required_windows_fragments = {
        "function Add-EnvDefault",
        "function Update-VncEnvDefaults",
        "[System.IO.File]::AppendAllText",
        *VNC_ENV_KEYS,
    }
    for fragment in required_windows_fragments:
        if fragment not in windows_source:
            raise SystemExit(f"Windows installer is missing {fragment}")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("dist", type=Path)
    args = parser.parse_args()
    repository_root = Path(__file__).resolve().parents[1]

    validate_installer_sources(repository_root)

    require_files(
        args.dist / "lazyfish-assistant-windows.zip",
        COMMON_FILES | {"scripts/lazyfish-windows.ps1"},
    )
    require_files(
        args.dist / "lazyfish-assistant-macos.zip",
        COMMON_FILES | {"scripts/lazyfish-macos.sh"},
    )
    print("Deployment kit noVNC contents passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
