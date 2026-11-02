# conform: tags=formatter,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=internal/cli/analysis_test.go:203 TestAnalysisCollectionRangesAndSymlinkConfinement
# header
import ListEntry, List from "@std/collections/collections.ms"

fn update(items: ListEntry[Int]) Int:
    return 0
