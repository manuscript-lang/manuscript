import (
    exercise from "./outer.ms",
    exercise_shared from "./shared.ms",
    read_file, remove, temporary_directory, temporary_root from "@std/os/fs.ms",
    expect_equal from "@std/test/test.ms",
)

test "same display names keep nested resource cleanup":
    let path = "{try temporary_root()}/ms-nominal-cycle-identity.txt"
    let _gone = remove(path, false)
    exercise(path.clone())

    let seen = try read_file(path.clone(), none).wait()
    let _cleaned = remove(path, false)
    seen.length() | try expect_equal(1)

fn expect_closed(path: String) Unit!:
    let seen = try read_file(path.clone(), none).wait()
    let _cleaned = remove(path, false)
    try expect_equal(seen.length(), 1)

test "shared generic field types keep cleanup for each value":
    let root = try temporary_directory("ms-shared-classification")
    let first = "{root}/ms-shared-first.txt"
    let second = "{root}/ms-shared-second.txt"
    let third = "{root}/ms-shared-third.txt"
    let fourth = "{root}/ms-shared-fourth.txt"
    exercise_shared(first.clone(), second.clone(), third.clone(), fourth.clone())
    try expect_closed(first)
    try expect_closed(second)
    try expect_closed(third)
    try expect_closed(fourth)
    try remove(root, false)
