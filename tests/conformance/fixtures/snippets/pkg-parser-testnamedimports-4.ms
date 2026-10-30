# conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:155 TestNamedImports
import (
    ListEntry,  # first
    MapEntry,
) from "@std/collections.ms"
