// expect-stdout: close gate
// expect-stdout: leaves: true
// A scope whose close fails leaves the function from the scope end: a record declared
// after the failing resource, with fields handed on, is settled before that end, so the
// exit has nothing left to release.
import (
	Bytes from "@std/bytes.ms",
	stdout from "@std/io/io.ms",
)

type Gate {
	name String
}

fn move Gate.close() Void! {
	stdout().write("close gate\n").get()
	return error(Error("gate"))
}

type Message {
	data Bytes
	kind Int
}

fn make() Message {
	return Message(data: Bytes(), kind: 1)
}

fn leaves() Void! {
	var _gate = Gate("g")
	message := make()
	forwarded := Message(data: message.data.clone(), kind: message.kind)
	if forwarded.kind == 0 { return ok() }

	return ok()
}

fn main() Void {
	r := leaves()
	stdout().write(f"leaves: {r.is_error()}\n").get()
}
