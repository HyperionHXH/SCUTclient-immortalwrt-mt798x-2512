#!/usr/bin/env python3
import pathlib
import sys


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: patch_scutclient.py <scutclient.lua>", file=sys.stderr)
        return 1

    path = pathlib.Path(sys.argv[1])
    text = path.read_text(encoding="utf-8")

    if "local function file_exists(path)" in text:
        return 0

    text = text.replace(
        'local fs = require "nixio.fs"',
        """local function file_exists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end""",
    )
    text = text.replace("fs.access(", "file_exists(")
    text = text.replace('fs.mkdirr("/var/etc")', 'os.execute("mkdir -p /var/etc")')
    text = text.replace("fs.mkdirr('/var/etc')", 'os.execute("mkdir -p /var/etc")')

    path.write_text(text, encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
