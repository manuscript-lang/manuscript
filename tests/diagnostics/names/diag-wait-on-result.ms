// conform: tags=diagnostics,tier-core
// conform: phase=check
import open from "@std/os/fs.ms"

export fn main() Int! {
	f := open("a").wait()?
	f.close()?
	return 0
}
// expect-error: MS2001 6:20 unknown or ambiguous member wait on FileHandle!; available: and_then, err, get, get_or, get_or_else, is_error, is_ok, map, map_error, or_else, to_optional; this call returns its Result directly, not a Promise, so drop `.wait()`
// expect-fix: 6:19-6:26 ""
// expect-error: MS3001 8:12 expected Int!, found Int (in the return value); wrap the value in ok(...) to return it as a success, e.g. return ok(value); when another argument is a Result call, unwrap that call with ? instead, e.g. expect_equal(f()?, value)?
