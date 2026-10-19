# conform: tags=formatter,lists,modules,parser,stdlib-collections,stdlib-system,strings,tier-io
# conform: phase=parse
# conform: origin=pkg/tooling/lsp/navigation_test.go:53 TestStandardLibraryNavigation
import ListBuilder from "@std/collections.ms"
import system from "@std/system.ms"
fn length(values: List[Int]) Int:
    return values.length()
fn os_name() String:
    return system().info().os
