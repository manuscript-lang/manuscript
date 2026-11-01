# conform: tags=formatter,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:155 TestNamedImports
import (
    ListEntry,  # first
    MapEntry,
) from "@std/collections/collections.ms"
