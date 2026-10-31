# conform: tags=diagnostics,lists,modules,stdlib-collections,stdlib-system,strings,tier-io
# conform: phase=check
# conform: origin=pkg/tooling/lsp/navigation_test.go:53 TestStandardLibraryNavigation
import ListEntry from "@std/collections.ms"
import system from "@std/process.ms"

fn length(values: List[Int]) Int:
    return values.length()

fn os_name() String:
    return system().info().os
