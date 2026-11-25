// conform: tags=diagnostics,maps,modules,records,stdlib-collections,tier-stdlib
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:75 TestCollectionPreludeAndShadowing
import Map from "@std/collections/collections.ms"

type Map[K, V] {
	value V
}
// expect-error: MS2003 4:8-4:11 redundant prelude import Map; remove Map from this import and use its prelude declaration directly
// expect-fix: 4:1-5:1 ""
// expect-error: MS2001 6:1 declaration Map reuses a prelude name; rename it, because Map always refers to the standard declaration
