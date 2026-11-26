// conform: tags=diagnostics
// conform: phase=check
import Set from "@std/collections/collections.ms"

type Set[T] {
	value T
}
// expect-error: MS2003 3:8-3:11 redundant prelude import Set; remove Set from this import and use its prelude declaration directly
// expect-fix: 3:1-4:1 ""
// expect-error: MS2001 5:1 declaration Set reuses a prelude name; rename it, because Set always refers to the standard declaration
