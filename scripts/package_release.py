#!/usr/bin/env python3
"""Package the repository addon and test the actual archive before delivery."""
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
from zipfile import ZIP_DEFLATED, ZipFile


def main():
    root = Path(__file__).resolve().parents[1]
    addon = root / "MDTHelper"
    toc = (addon / "MDTHelper.toc").read_text(encoding="utf-8")
    match = re.search(r"^## Version: ([0-9]+(?:\.[0-9]+)+)$", toc, re.MULTILINE)
    if not match:
        raise SystemExit("Missing or invalid TOC version")
    output = root / f"MDTHelper.{match[1]}.zip"
    if output.exists():
        raise SystemExit(f"Refusing to overwrite an existing release: {output}")

    lua = shutil.which("lua5.1")
    luac = shutil.which("luac5.1")
    if not lua or not luac:
        raise SystemExit("Release checks require lua5.1 and luac5.1")

    with tempfile.TemporaryDirectory(prefix="mdthelper-release-") as temp:
        staging = Path(temp)
        archive = staging / output.name
        files = sorted(path for path in addon.rglob("*") if path.is_file())
        with ZipFile(archive, "w", ZIP_DEFLATED, compresslevel=9) as package:
            for path in files:
                package.write(path, path.relative_to(root).as_posix())
        extracted = staging / "extracted"
        with ZipFile(archive) as package:
            assert package.testzip() is None, "Archive CRC check failed"
            for path in files:
                assert package.read(path.relative_to(root).as_posix()) == path.read_bytes()
            package.extractall(extracted)

        shutil.copytree(root / "tests", extracted / "tests")
        sources = sorted((extracted / "MDTHelper").glob("*.lua"))
        subprocess.run([luac, "-p", *map(str, sources)], check=True)
        suites = sorted((extracted / "tests").glob("*_test.lua"))
        if not suites:
            raise SystemExit("No release test suites found")
        for suite in suites:
            subprocess.run([lua, str(suite)], cwd=extracted, check=True)
        # Publish the local artifact only after its extracted code passes.
        with output.open("xb") as destination:
            destination.write(archive.read_bytes())
    print(f"Verified release: {output}")


if __name__ == "__main__":
    main()
