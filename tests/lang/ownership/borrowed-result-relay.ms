// conform: tags=testing,tier-stdlib
// conform: phase=test
import expect_equal from "@std/test/test.ms"

// A call that answers `&T!` borrows its success value from an argument; an error it
// builds is its own. `?` takes that error out without copying it, `error(cause)` of a
// borrowed `cause` answers a borrow of it, and `(f()?) or d` moves the payload into the
// binding that owns it.
type Cause {
	code Int
	text String
}

fn pick(hold causes List[Cause], at Int) &Cause! {
	if at < 0 { return error(Error("negative", kind: "EINVAL")) }
	if at >= causes.length() { return error(Error("past the end", kind: "ERANGE")) }

	return ok(causes[at])
}

fn text_of(hold causes List[Cause], at Int) String! {
	cause := pick(causes, at).clone()?
	return ok(cause.text)
}

fn build() List[Cause] {
	return [Cause(1, "one"), Cause(2, "two")]
}

fn code_at(at Int) Int! {
	cause := pick(build(), at)?
	return ok(cause.code)
}

fn relay(hold outcome Cause!) &Cause! {
	match outcome {
		ok(value) => {
			return ok(value)
		}
		error(cause) => {
			return error(cause)
		}
	}
}

fn code_of(hold outcome Cause!) Int! {
	cause := relay(outcome).clone()?
	return ok(cause.code)
}

fn written(at Int) String?! {
	if at < 0 { return error(Error("unreadable", kind: "EIO")) }
	if at == 0 { return ok(null) }

	return ok(f"line {at}")
}

fn first_line(at Int) String! {
	line := (written(at)?) or "none"
	return ok(line)
}

test "? takes the error of a borrowing call out" {
	causes := [Cause(1, "one"), Cause(2, "two")]
	expect_equal(text_of(causes, 1)?, "two")?
	expect_equal(text_of(causes, -1).err().kind, "EINVAL")?
	expect_equal(text_of(causes, 2).err().kind, "ERANGE")?
}

test "error(cause) of a borrowed cause is relayed once" {
	failed Cause! := error(Error("cause held", kind: "ECAUSE"))
	expect_equal(code_of(failed).err().kind, "ECAUSE")?

	fine Cause! := ok(Cause(7, "seven"))
	expect_equal(code_of(fine)?, 7)?
}

test "(f()?) or d owns what it unwraps" {
	expect_equal(first_line(3)?, "line 3")?
	expect_equal(first_line(0)?, "none")?
	expect_equal(first_line(-1).err().kind, "EIO")?
}

test "? on a call over a temporary takes the error the call built" {
	expect_equal(code_at(1)?, 2)?
	expect_equal(code_at(-1).err().kind, "EINVAL")?
	expect_equal(code_at(9).err().kind, "ERANGE")?
}
// expect-exit: 0
// expect-tests: passed=4 failed=0
