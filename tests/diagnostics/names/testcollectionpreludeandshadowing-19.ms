// conform: tags=diagnostics,formatter,modules,records,sets,stdlib-collections,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/compiler/prelude_test.go:81 TestCollectionPreludeAndShadowing
import Set from "@std/collections/collections.ms"

type Set[T] {
	value T
}
// expect-error: MS2003 4:8-4:11 redundant prelude import Set; remove Set from this import and use its prelude declaration directly
// expect-fix: 4:1-5:1 ""
// expect-error: MS2001 6:1 declaration Set reuses a prelude name; rename it, because Set always refers to the standard declaration
