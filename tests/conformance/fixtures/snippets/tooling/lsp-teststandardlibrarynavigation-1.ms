// conform: tags=diagnostics,lists,modules,stdlib-collections,stdlib-system,strings,tier-io
// conform: phase=check
// conform: origin=pkg/tooling/lsp/navigation_test.go:53 TestStandardLibraryNavigation
import (
	ListEntry from "@std/collections/collections.ms",
	system_info from "@std/os/system.ms",
)

fn length(values List[Int]) Int {
	return values.length()
}

fn os_name() String {
	return system_info().os
}
// expect-error: MS2003 5:5-5:14 redundant prelude import ListEntry; remove ListEntry from this import and use its prelude declaration directly
// expect-fix: 5:1-6:1 ""
