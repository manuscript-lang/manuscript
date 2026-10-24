# conform: tags=formatter,lists,modules,parser,stdlib-collections,stdlib-system,strings,tier-io
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/navigation_test.go:53 TestStandardLibraryNavigation
from "@std/collections.ms" import ListBuilder
from "@std/process.ms" import system

def length(values: List[Int]) -> Int:
    return values.length()

def os_name() -> String:
    return system().info().os
