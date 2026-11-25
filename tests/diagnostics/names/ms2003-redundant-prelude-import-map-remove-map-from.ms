// conform: tags=diagnostics
// conform: phase=check
import Map from "@std/collections/collections.ms"

type Map[K, V] {
	value V
}
// expect-error: MS2003 3:8-3:11 redundant prelude import Map; remove Map from this import and use its prelude declaration directly
// expect-fix: 3:1-4:1 ""
// expect-error: MS2001 5:1 declaration Map reuses a prelude name; rename it, because Map always refers to the standard declaration
