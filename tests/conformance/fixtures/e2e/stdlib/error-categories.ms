// conform: tags=testing,tier-io
// conform: phase=test
import (
	range_by from "@std/collections/collections.ms",
	hex_decode from "@std/data/encoding.ms",
	canonicalize from "@std/os/fs.ms",
	expect_equal, expect_true from "@std/test/test.ms",
)

// Standard failures are Error values whose kind callers compare, whatever package
// raised them.

fn is_missing(cause: Error) Bool:
	return cause.kind == "ENOENT"

test "failures of different packages share one kind vocabulary":
	is_missing(canonicalize("/no/such/path/for/manuscript").err()) | expect_true?
	hex_decode(text: "zz", max_bytes: 10).err().kind | expect_equal("EBADMSG")?
	hex_decode(text: "aa", max_bytes: -1).err().kind | expect_equal("EINVAL")?

test "a limit failure keeps its kind through try":
	allocation := range_by(start: 0, end: 268435457, step: 1)
	allocation.err().kind | expect_equal("EOVERFLOW")?

test "an Error built by hand compares by message, kind and details":
	left := Error("same", kind: "ETIMEDOUT", details: {"op": "read"})
	right := Error("same", kind: "ETIMEDOUT", details: {"op": "read"})
	left | expect_equal(right)?
	(left == Error("same", kind: "ETIMEDOUT")) | expect_equal(false)?
