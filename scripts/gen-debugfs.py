#!/usr/bin/env python3
"""Generate a debugfs batch script that copies an overlay tree into an ext4
filesystem image.

Usage:
    gen-debugfs.py <overlay-dir>

debugfs has no recursive copy, so we walk the tree ourselves and emit
mkdir/write/symlink/sif commands.  Paths must not contain whitespace, which
is fine for the Droidian adaptation tree.

This runs unprivileged; ownership is forced to root:root because everything
we inject belongs to the system.
"""

import os
import stat
import sys


def quote(path):
    # debugfs splits on whitespace; none of our paths contain it.
    return path


def emit_for_dir(path):
    return [
        f"mkdir {quote(path)}",
        f"sif {quote(path)} mode 040755",
        f"sif {quote(path)} uid 0",
        f"sif {quote(path)} gid 0",
    ]


def walk(root):
    """Yield (host_path, fs_path) for every entry below root, parents first."""
    stack = [("", root)]
    while stack:
        rel, host = stack.pop()
        entries = sorted(os.scandir(host), key=lambda e: e.name)
        # Re-add children in reverse so the stack pops them in sorted order.
        for entry in reversed(entries):
            child_rel = os.path.join(rel, entry.name) if rel else entry.name
            fs_path = "/" + child_rel
            yield fs_path, entry
        for entry in reversed(entries):
            if entry.is_dir(follow_symlinks=False) and not entry.is_symlink():
                child_rel = os.path.join(rel, entry.name) if rel else entry.name
                stack.append((child_rel, entry.path))


def main():
    if len(sys.argv) != 2:
        print(__doc__, file=sys.stderr)
        return 1

    root = os.path.abspath(sys.argv[1])
    if not os.path.isdir(root):
        print(f"not a directory: {root}", file=sys.stderr)
        return 1

    lines = []
    dirs = []
    files = []
    links = []

    for fs_path, entry in walk(root):
        if entry.is_symlink():
            links.append((fs_path, os.readlink(entry.path)))
        elif entry.is_dir(follow_symlinks=False):
            dirs.append(fs_path)
        elif entry.is_file(follow_symlinks=False):
            files.append((fs_path, entry.path))
        else:
            print(f"skipping special file: {entry.path}", file=sys.stderr)

    for path in dirs:
        lines.extend(emit_for_dir(path))

    for fs_path, host_path in files:
        # debugfs' "sif mode" takes the full st_mode, including the file
        # type bits.  Passing only the permission bits makes the inode
        # typeless, and the next e2fsck removes the file.  Always OR in
        # S_IFREG.
        mode = stat.S_IFREG | stat.S_IMODE(os.stat(host_path).st_mode)
        lines.append(f"rm {quote(fs_path)}")
        lines.append(f"write {host_path} {quote(fs_path)}")
        lines.append(f"sif {quote(fs_path)} mode 0{mode:o}")
        lines.append(f"sif {quote(fs_path)} uid 0")
        lines.append(f"sif {quote(fs_path)} gid 0")

    for fs_path, target in links:
        lines.append(f"rm {quote(fs_path)}")
        lines.append(f"symlink {quote(fs_path)} {target}")

    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main())
