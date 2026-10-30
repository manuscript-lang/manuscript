# conform: tags=formatter,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/parser/parser_test.go:155 TestNamedImports
import (
    ListBuilder,  # first
    MapBuilder,
) from "@std/collections.ms"
