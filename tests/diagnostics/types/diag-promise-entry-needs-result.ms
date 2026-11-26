// conform: tags=diagnostics,tier-core
// conform: phase=check
import promise from "@std/concurrency/promise.ms"

fn compute() Int {
	return 1
}

export fn main() Int! {
	p := promise(() => compute())
	print(p.wait()?)
	return 0
}
// expect-error: MS3000 10:18 the callback returns Int, but this parameter needs a function returning U!; a Result-returning callback reports failure as a value, so wrap the value in ok(...), e.g. fn: ok(value)
// expect-fix: 10:24-10:33 "ok(compute())"
// expect-error: MS3001 12:12 expected Int!, found Int (in the return value); wrap the value in ok(...) to return it as a success, e.g. return ok(value); when another argument is a Result call, unwrap that call with ? instead, e.g. expect_equal(f()?, value)?
