import files from "@assets"
import walk from "@std/os/tree.ms"
import expect_equal, expect_error, expect_ok from "@std/test/test.ms"

test "embedded files read back byte for byte":
    let tree = files()
    tree.read("hello.txt", none) | try expect_ok | try expect_equal(
        "hello \{braces\} and \"quotes\"\n".to_bytes()
    )
    tree.read("nested/deep.txt", none) | try expect_ok | try expect_equal(
        "deep\n".to_bytes()
    )

    let data = tree.read("data.bin", none) | try expect_ok
    data.length() | try expect_equal(256)
    data.get(255, 0).to_int() | try expect_equal(255)

test "embedded tree walks in name order":
    let found = walk(files()) | try expect_ok
    found.map(
        fn e: e.path.clone()
    ) | try expect_equal(["data.bin", "hello.txt", "nested", "nested/deep.txt"])

test "missing embedded files report NotFound":
    files().read(
        "nope.txt", none
    ) | try expect_error | try expect_equal(
        Error(
            "filesystem: file or directory not found", kind: "ENOENT"
        )
    )

test "embedded trees respect read limits and directories":
    let tree = files()
    tree.read(
        "data.bin", 10
    ) | try expect_error | try expect_equal(
        Error("filesystem: limit exceeded", kind: "EOVERFLOW")
    )
    tree.read(
        "nested", none
    ) | try expect_error | try expect_equal(
        Error("filesystem: invalid input", kind: "EINVAL")
    )
    tree.children(
        "hello.txt", none
    ) | try expect_error | try expect_equal(
        Error("filesystem: invalid input", kind: "EINVAL")
    )
