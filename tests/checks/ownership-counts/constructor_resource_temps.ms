// expect-stdout: body 42
// expect-stdout: close 1
// expect-stdout: close 2
// expect-stdout: false
// expect-stdout: close 2
// expect-stdout: close 1
// expect-stdout: true
// Scalar-backed resources still have cleanup duties while constructor fields are
// pending.
import Closeable from "@std/core.ms"

type Token:
	id: Int

fn move Token.close() Void!:
	print(f"close {self.id}")

type Wrapped:
	second: Token!
	code: Int
	first: Token?

fn check(fail: Bool) Int!:
	if fail: return error(Error("field failed"))
	return ok(42)

fn build(fail: Bool) Void!:
	value := Wrapped(first: Token(1), second: ok(Token(2)), code: check(fail)?)
	print(f"body {value.code}")

fn main() Void:
	print(build(false).is_error())
	print(build(true).is_error())
