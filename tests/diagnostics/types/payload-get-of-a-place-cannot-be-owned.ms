// conform: tags=scope-cleanup,optional,tier-core
// conform: phase=check
// The payload `get` reads out of an `Optional` that a parameter or field keeps stays
// there. Returning it would make a second owner: a resource would close twice. Read it
// in place, or consume the whole `Optional` parameter at its last use.
import panic from "@std/core.ms"

type Handle {
	id Int
	note String
}

fn move Handle.close() Void! {
	print("closed")
}

type Slot[T] {
	value T?
}

fn unwrap_field(hold s Slot[Handle]) &Handle {
	return s.value or panic("called Optional.get() on null")
}

fn unwrap_generic[T](hold s Slot[T]) &T {
	return s.value or panic("called Optional.get() on null")
}
// expect-error: MS3000 22:20 cannot move `s.value or ..` out: it is read in place from `s.value`, which keeps it; it has one owner and no `clone`, so use it in place or move `s.value` itself
// expect-error: MS3000 26:20 cannot move `s.value or ..` out: it is read in place from `s.value`, which keeps it; it has one owner and no `clone`, so use it in place or move `s.value` itself
