import expect_equal, expect_true from "@std/test/test.ms"
import range_by from "@std/collections/collections.ms"
import canonicalize from "@std/os/fs.ms"
import hex_decode from "@std/data/encoding.ms"

# Standard failures are Error values whose kind callers compare, whatever package raised them.

fn is_missing(cause: Error) Bool:
    return cause.kind == ErrorCategory.NotFound

test "failures of different packages share one kind vocabulary":
    is_missing(canonicalize("/no/such/path/for/manuscript").err()) | try expect_true
    hex_decode(text: "zz", max_bytes: 10).err().kind | try expect_equal(
        ErrorCategory.InvalidData
    )
    hex_decode(text: "aa", max_bytes: -1).err().kind | try expect_equal(
        ErrorCategory.InvalidInput
    )

test "a limit failure keeps its kind through try":
    let allocation = range_by(start: 0, end: 268435457, step: 1)
    allocation.err().kind | try expect_equal(ErrorCategory.LimitExceeded)

test "an Error built by hand compares by message, kind and details":
    let left = Error("same", kind: Timeout, details: {"op": "read"})
    let right = Error("same", kind: Timeout, details: {"op": "read"})
    left | try expect_equal(right)
    (left == Error("same", kind: Timeout)) | try expect_equal(false)
