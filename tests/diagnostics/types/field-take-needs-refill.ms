// conform: tags=scope-cleanup,diagnostics,tier-core
// conform: phase=check
// A resource cannot leave a holder that stays in use: the holder would close with a
// hole in it. Taking the field and refilling it in the next statement is the way (see
// `ReadStream.end`).
import Closeable from "@std/core.ms"

type Half {
	id Int
}

fn move Half.close() Void! {
	print(f"close {self.id}")
}

type Pair {
	first Half
	second Half
}

fn end_first(var pair Pair) Void! {
	pair.first.close()?
}
// expect-error: MS3000 22:10 cannot move the resource `pair.first` out of `pair`: a resource cannot be cloned, and it leaves `pair` only when `pair` is a local binding or a parameter and no type on the path has a `close` of its own; use `pair.first` in place, move the whole `pair`, or take it with `part := pair.first` and refill `pair.first = ...` in the next statement
