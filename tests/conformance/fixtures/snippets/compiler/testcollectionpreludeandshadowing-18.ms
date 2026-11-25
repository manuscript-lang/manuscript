// conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
// conform: phase=check
// conform: origin=pkg/compiler/prelude_test.go:80 TestCollectionPreludeAndShadowing
import Set from "@std/collections/collections.ms"
// expect-error: MS2003 4:8-4:11 redundant prelude import Set; remove Set from this import and use its prelude declaration directly
// expect-fix: 4:1-5:1 ""
