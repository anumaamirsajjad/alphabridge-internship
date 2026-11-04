"""Checks that the Docker image copies every module the app imports at startup.

What this file does:
    Reads the top-level modules that presentation/main.py imports from this project, and checks
    that the Dockerfile copies each one. A missing copy only shows up inside the container, where
    the app crashes on startup. The unit tests run from the source folder, so they cannot catch it.
"""

import re
from pathlib import Path

API_DIR = Path(__file__).resolve().parents[3]
PROJECT_MODULES = {"events", "business", "data", "validation", "presentation"}


def imported_project_modules():
    main_source = (API_DIR / "presentation" / "main.py").read_text(encoding="utf-8")
    found = set()
    for line in main_source.splitlines():
        match = re.match(r"\s*(?:from|import)\s+([A-Za-z_][A-Za-z0-9_]*)", line)
        if match and match.group(1) in PROJECT_MODULES:
            found.add(match.group(1))
    return found


def copied_by_dockerfile():
    dockerfile = (API_DIR / "Dockerfile").read_text(encoding="utf-8")
    copied = set()
    for line in dockerfile.splitlines():
        match = re.match(r"\s*COPY\s+(\S+)", line)
        if match:
            copied.add(match.group(1).rstrip("/").removesuffix(".py"))
    return copied


def test_every_imported_project_module_is_copied_into_the_image():
    missing = imported_project_modules() - copied_by_dockerfile()
    assert not missing, f"Dockerfile does not copy these modules, so the container will crash: {sorted(missing)}"
