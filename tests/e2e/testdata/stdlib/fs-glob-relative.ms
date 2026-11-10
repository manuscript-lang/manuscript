import (
    Closeable from "@std/core.ms",
    change_directory, working_directory from "@std/os/env.ms",
    GlobOptions,
    PathEntry,
    create_directory,
    glob,
    temporary,
    write_file from "@std/os/fs.ms",
    expect_equal from "@std/test/test.ms",
)

type RestoreDirectory:
    path: String

impl Closeable for RestoreDirectory:
    var fn close() Unit!:
        return change_directory(self.path)

fn matched_paths(root: String, options: GlobOptions) List[String]!:
    entries := try glob(root, options)
    return ok(entries.map(fn(entry: PathEntry) String: entry.path.clone()))

test "glob keeps dot named and parent query results relative to their root":
    directory := try temporary("manuscript-glob-relative-")
    _restore := RestoreDirectory(try working_directory())
    try create_directory("{directory.path()}/src/deep", recursive: true)
    for name in ["a.txt", "café.txt", "src/b.txt", "src/deep/c.txt"]:
        try write_file("{directory.path()}/{name}", "file").wait()
    try change_directory(directory.path())

    all := GlobOptions(patterns: ["**/*.txt"])
    expected := ["a.txt", "café.txt", "src/b.txt", "src/deep/c.txt"]
    for root in [".", "./", "src/..", directory.path()]:
        try expect_equal(try matched_paths(root, all), expected)
    try expect_equal(
        try matched_paths(".", GlobOptions(patterns: ["*.txt"])), ["a.txt", "café.txt"]
    )
    try expect_equal(try matched_paths("src", all), ["b.txt", "deep/c.txt"])
    try expect_equal(
        try matched_paths("src", GlobOptions(patterns: ["../*.txt"])),
        ["../a.txt", "../café.txt"]
    )
    try expect_equal(
        try matched_paths(
            ".", GlobOptions(patterns: ["**/*.txt"], exclude: ["src/**"])
        ),
        ["a.txt", "café.txt"]
    )

    selected := try glob(".", all, fn(entry: PathEntry) Bool: entry.path == "src")
    try expect_equal(
        selected.map(fn(entry: PathEntry) String: entry.path.clone()),
        ["a.txt", "café.txt"]
    )
