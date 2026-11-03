import exercise from "./outer.ms"
import read_file, remove, temporary_root from "@std/os/fs.ms"
import expect_equal from "@std/test/test.ms"

test "same display names keep nested resource cleanup":
    let path = "{try temporary_root()}/ms-nominal-cycle-identity.txt"
    let _gone = remove(path, false)
    exercise(path.clone())
    let seen = try read_file(path.clone(), none)
    let _cleaned = remove(path, false)
    seen.length() | try expect_equal(1)
