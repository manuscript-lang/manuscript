import expect_equal from "@std/test/test.ms"
import first from "./first.ms"
import second from "./second.ms"

test "shared bound native thunks use each invocation file and line":
    let absent: Int? = none
    try expect_equal(second(absent).err().message(), "missing value at second.ms:4")
    try expect_equal(first(absent).err().message(), "missing value at first.ms:3")
    try expect_equal(second(absent).err().message(), "missing value at second.ms:4")
