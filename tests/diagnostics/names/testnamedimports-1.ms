// conform: tags=diagnostics,formatter,modules,stdlib-collections,tier-stdlib
// conform: phase=check,parse
// conform: origin=pkg/parser/parser_test.go:152 TestNamedImports
import ListEntry from "@std/collections/collections.ms"
// expect-error: MS2003 4:8-4:17 redundant prelude import ListEntry; remove ListEntry from this import and use its prelude declaration directly
// expect-fix: 4:1-5:1 ""
