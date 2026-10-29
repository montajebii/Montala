#!/usr/bin/env python3
"""Create a .zip from a directory or file, without needing the `zip` binary.

Usage:
    python3 tools/make_zip.py OUT.zip SRC [ARCNAME]

If SRC is a directory it is stored recursively under ARCNAME (default: the
directory's basename). Reproducible: entries are written in sorted order with a
fixed timestamp so identical trees produce identical archives.
"""

import os
import sys
import time
import zipfile

FIXED_DATE = (1980, 1, 1, 0, 0, 0)


def add_tree(zf, src_dir, arc_root):
    for root, dirs, files in os.walk(src_dir):
        dirs.sort()
        for name in sorted(files):
            full = os.path.join(root, name)
            rel = os.path.relpath(full, src_dir)
            arc = os.path.join(arc_root, rel).replace(os.sep, "/")
            info = zipfile.ZipInfo(arc, date_time=FIXED_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            with open(full, "rb") as fh:
                zf.writestr(info, fh.read())


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    out, src = argv[0], argv[1]
    if os.path.isdir(src):
        arc_root = argv[2] if len(argv) > 2 else os.path.basename(src.rstrip("/"))
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
            add_tree(zf, src, arc_root)
    else:
        arc = argv[2] if len(argv) > 2 else os.path.basename(src)
        with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED) as zf:
            info = zipfile.ZipInfo(arc, date_time=FIXED_DATE)
            info.compress_type = zipfile.ZIP_DEFLATED
            with open(src, "rb") as fh:
                zf.writestr(info, fh.read())
    size = os.path.getsize(out)
    print(f"wrote {out} ({size / 1048576:.1f} MB)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
