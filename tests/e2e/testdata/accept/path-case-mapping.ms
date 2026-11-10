import (
    posix, win32 from "@std/os/path.ms",
    expect_equal from "@std/test/test.ms",
)

test "Windows relative paths retain scalar lowercase comparisons":
    paths := win32()
    try expect_equal(try paths.relative("C:/ΟΣ", "C:/οσ"), "")
    try expect_equal(try paths.relative("C:/ΟΣ/a", "C:/οσ/b"), "..\\b")
    try expect_equal(try paths.relative("C:/AΣ.TXT/a", "C:/aσ.txt/b"), "..\\b")
    try expect_equal(try paths.relative("C:/AΣ́/a", "C:/aσ́/b"), "..\\b")
    try expect_equal(try paths.relative("C:/ΟΣ/a", "C:/ος/b"), "..\\..\\ος\\b")
    try expect_equal(try paths.relative("C:/İ/a", "C:/i̇/b"), "..\\b")
    try expect_equal(try paths.relative("C:/Alpha/a", "c:/alpha/b"), "..\\b")

test "Windows UNC roots retain scalar lowercase comparisons":
    paths := win32()
    try expect_equal(try paths.relative("//ΟΣ/share/a", "//οσ/share/b"), "..\\b")
    try expect_equal(try paths.relative("//host/ΟΣ/a", "//host/οσ/b"), "..\\b")
    try expect_equal(
        try paths.resolve("//ΟΣ/share/base", ["//οσ/share/child"]),
        "\\\\οσ\\share\\child"
    )

test "POSIX path comparison remains case sensitive":
    try expect_equal(try posix().relative("/ΟΣ", "/οσ"), "../οσ")
    try expect_equal(try posix().relative("/ΟΣ", "/ος"), "../ος")
