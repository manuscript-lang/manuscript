// expect-stdout: close 3
// expect-stdout: close 2
// expect-stdout: close 1
// Fields close last-declared first; the record's own close would run before them.
import (
	Closeable from "@std/core.ms",
	stdout from "@std/io/io.ms",
)

type Res:
	id: Int

fn var Res.close() Unit!:
	stdout().write("close {self.id}\n").get()

type Pair:
	a: Res
	b: Res

export fn main() Int:
	p := Pair(a: Res(1), b: Res(2))
	_c := Res(3)
	return p.a.id - 1
