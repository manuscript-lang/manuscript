// conform: tags=diagnostics
// conform: phase=check
import (
	ListBuilder from "@std/collections/collections.ms",
	system from "@std/system.ms",
)

fn length(values List[Int]) Int {
	return values.length()
}

fn os_name() String {
	return system().info().os
}
// expect-error: MS2002 4:5-4:16 module does not export ListBuilder; @std/collections/collections.ms exports: List, ListEntry, Map, MapEntry, Numeric, Pair, Partition, RangeOptions, SearchResult, Set, filled, flatten, ...; namespace imports are unsupported, so import individual exports with 'import Name, OtherName from "@std/collections/collections.ms"'
// expect-error: MS2002 5:5-5:11 unknown standard module @std/system.ms; did you mean '@std/os/system.ms'?
// expect-error: MS2001 13:12 unknown binding system; host handle getters were removed: import the operation itself, e.g. read_file from "@std/os/fs.ms", connect from "@std/net/net.ms", run from "@std/os/process.ms", now from "@std/time.ms"
