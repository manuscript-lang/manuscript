// conform: tags=testing,tier-core,ownership
// conform: phase=test
import (
	expect_equal from "@std/test/test.ms",
)

// `match call()? { .. }` moves the payload out of the call's Result, so an arm that hands
// its binding on moves it instead of copying it. `pass` takes its result as a borrowed
// view of the temporary, nine times over: the table that tracks those views once held
// eight and copied every payload after them.
fn make() String?! {
	return ok("a string long enough to live on the heap")
}

fn nothing() String?! {
	return ok(null)
}

fn take(move text String) Int {
	return text.length()
}

fn pass[T](hold result T!) &T! => result

fn arm_length() Int! {
	match make()? {
		message => {
			return ok(take(message))
		}
		null => {
			return ok(-1)
		}
	}
}

fn null_arm() Int! {
	match nothing()? {
		message => {
			return ok(take(message))
		}
		null => {
			return ok(-1)
		}
	}
}

fn many_views() Int! {
	a := pass(result: make())?
	b := pass(result: make())?
	c := pass(result: make())?
	d := pass(result: make())?
	e := pass(result: make())?
	f := pass(result: make())?
	g := pass(result: make())?
	h := pass(result: make())?
	i := pass(result: make())?
	j := pass(result: make())?
	return ok((a or "").length() + (j or "").length() + (b or "").length() + (c or "").length() + (d or "").length() + (e or "").length() + (f or "").length() + (g or "").length() + (h or "").length() + (i or "").length())
}

test "an arm over a try owns its payload and hands it on without a copy" {
	expect_equal(arm_length()?, 40)?
	expect_equal(null_arm()?, -1)?
	expect_equal(many_views()?, 400)?
}
// expect-exit: 0
// expect-tests: passed=1 failed=0
