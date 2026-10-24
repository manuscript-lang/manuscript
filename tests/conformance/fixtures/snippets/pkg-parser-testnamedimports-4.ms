# conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=pkg/parser/parser_test.go:155 TestNamedImports
from "@std/collections.ms" import (
    ListBuilder,  # first
    MapBuilder,
)
