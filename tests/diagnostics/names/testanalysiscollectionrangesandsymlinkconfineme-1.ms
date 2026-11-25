// conform: tags=diagnostics,formatter,modules,stdlib-collections,tier-stdlib
// conform: phase=check,parse
// conform: origin=internal/cli/analysis_test.go:203 TestAnalysisCollectionRangesAndSymlinkConfinement
// header
import List, ListEntry from "@std/collections/collections.ms"

fn update(items ListEntry[Int]) Int {
	return 0
}
// expect-error: MS2003 5:8-5:12 redundant prelude import List; remove List from this import and use its prelude declaration directly
// expect-fix: 5:8-5:14 ""
// expect-error: MS2003 5:14-5:23 redundant prelude import ListEntry; remove ListEntry from this import and use its prelude declaration directly
// expect-fix: 5:12-5:23 ""
