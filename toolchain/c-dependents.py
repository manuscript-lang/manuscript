#!/usr/bin/env python3
"""Prints the C sources and headers of src/runtime/ and src/compiler/ that include, directly or through other files, one of the
files named on the command line (the files themselves are printed too), one per line. An include is matched by file
name, so a header with a common name pulls in a few extra files; that only costs lint time, never a missed file.
toolchain/c-lint.sh uses it to run clang-tidy on what a changed header can affect. Usage: c-dependents.py <file>..."""
import os, re, sys

ROOTS = ("src/runtime", "src/compiler")
INCLUDE = re.compile(r'^\s*#\s*include\s*[<"]([^>"]+)[>"]', re.M)


def sources():
    for root in ROOTS:
        for directory, _, names in os.walk(root):
            for name in names:
                if name.endswith((".c", ".h")):
                    yield os.path.join(directory, name)


def main(changed):
    included_by = {}  # base name of an included file -> files that include it
    for path in sources():
        with open(path, encoding="utf-8", errors="replace") as handle:
            for target in INCLUDE.findall(handle.read()):
                included_by.setdefault(os.path.basename(target), set()).add(path)
    reached = set(changed)
    queue = list(changed)
    while queue:
        for user in included_by.get(os.path.basename(queue.pop()), ()):
            if user not in reached:
                reached.add(user)
                queue.append(user)
    print("\n".join(sorted(reached)))


if __name__ == "__main__":
    main(sys.argv[1:])
