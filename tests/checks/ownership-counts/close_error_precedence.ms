// expect-stdout: close 2
// expect-stdout: close 1
// expect-stdout: original body
// expect-stdout: EBODY
// expect-stdout: body
// expect-stdout: close 3
// expect-stdout: caller error
// expect-stdout: ECALLER
// expect-stdout: caller
// expect-stdout: caller error
// expect-stdout: caller
import Closeable from "@std/core.ms"

type Token:
	id Int

fn move Token.close() Void!:
	print(f"close {self.id}")
	return error(Error("close failed", kind: "ECLOSE"))

fn owned() Int!:
	_first := Token(1)
	_second := Token(2)
	return error(Error("original body", kind: "EBODY", details: {"id": "body"}))

fn borrowed(cause Error) Int!:
	_resource := Token(3)
	return error(cause)

fn main() Void:
	first := owned()
	cause := first.err()
	print(cause.message)
	print(cause.kind or "")
	print(cause.details["id"])

	original := Error("caller error", kind: "ECALLER", details: {"id": "caller"})
	second := borrowed(original)
	returned := second.err()
	print(returned.message)
	print(returned.kind or "")
	print(returned.details["id"])
	print(original.message)
	print(original.details["id"])
