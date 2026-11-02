# conform: tags=control-flow,formatter,lists,modules,parser,stdlib-testing,testing,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/accept/int-identities.ms
import expect_equal, expect_true from "@std/test/test.ms"

fn touch(var log: List[Int], value: Int) Int:
    log.append(value)
    return value

test "identities keep boundaries":
    for x in [-9223372036854775808, 9223372036854775807, -7, 0, 1]:
        ((x + 0 == x)) | try expect_true
        ((0 + x == x)) | try expect_true
        ((x - 0 == x)) | try expect_true
        ((x * 0 == 0)) | try expect_true
        ((0 * x == 0)) | try expect_true
        ((x * 1 == x)) | try expect_true
        ((1 * x == x)) | try expect_true
        ((x / 1 == x)) | try expect_true
        ((x % 1 == 0)) | try expect_true

test "identities keep operand effects":
    var log: List[Int] = []
    ((touch(var log, 1) * 0 == 0)) | try expect_true
    ((0 * touch(var log, 2) == 0)) | try expect_true
    ((touch(var log, 3) * 1 == 3)) | try expect_true
    ((1 * touch(var log, 4) == 4)) | try expect_true
    ((touch(var log, 5) + 0 == 5)) | try expect_true
    ((0 + touch(var log, 6) == 6)) | try expect_true
    ((touch(var log, 7) - 0 == 7)) | try expect_true
    ((touch(var log, 8) / 1 == 8)) | try expect_true
    ((touch(var log, 9) % 1 == 0)) | try expect_true
    log | try expect_equal([1, 2, 3, 4, 5, 6, 7, 8, 9])
