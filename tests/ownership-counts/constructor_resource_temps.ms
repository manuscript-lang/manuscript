// expect-stdout: body 42
// expect-stdout: close 2
// expect-stdout: close 1
// expect-stdout: false
// expect-stdout: close 2
// expect-stdout: close 1
// expect-stdout: true
// Scalar-backed resources still have cleanup duties while constructor fields are
// pending.
import Closeable from "@std/core.ms"

type Token:
	id: Int

fn var Token.close() Void!:
	print("close {self.id}")

type Wrapped:
	first: Token?
	second: Token!
	code: Int

fn check(fail: Bool) Int!:
	if fail: return error(Error("field failed"))
	return ok(42)

fn build(fail: Bool) Void!:
	value := Wrapped(Token(1), ok(Token(2)), check(fail)?)
	print("body {value.code}")

fn main() Void:
	print(build(false).is_error())
	print(build(true).is_error())
