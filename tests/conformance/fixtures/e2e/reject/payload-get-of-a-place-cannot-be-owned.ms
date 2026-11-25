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
