# conform: tags=modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=pkg/parser/partial_test.go:46 TestPartialGroupedImportsPreserveSymbolOffsets
fn first() Int:
    return 1
import {
ListBuilder,
MapBuilder,
} from "@std/collections.ms"
fn broken(
fn later() Int:
    return 2
