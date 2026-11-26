// conform: tags=scope-cleanup,diagnostics,tier-core
// conform: phase=check
// An element never leaves its list: the list closes every element it holds, so a `move`
// receiver taken from an index is rejected whatever the list is bound to.
import Closeable from "@std/core.ms"

type Item {
	label String
}

fn move Item.close() Void! => ok()

fn close_first(members List[Item]) Void! {
	members[0].close()?
	return ok()
}

fn main() Void! {
	close_first([Item("a")])?
	return ok()
}
// expect-error: MS3000 14:5 cannot move the resource `members[..]` out of `members`: a resource cannot be cloned, and it leaves `members` only when `members` is a local binding or a parameter and no type on the path has a `close` of its own; use `members[..]` in place, move the whole `members`, or take it with `part := members[..]` and refill `members[..] = ...` in the next statement
