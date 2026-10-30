# conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=internal/cli/analysis_test.go:203 TestAnalysisCollectionRangesAndSymlinkConfinement
# header
import ListBuilder, List from "@std/collections.ms"

fn update(items: ListBuilder[Int]) Int:
    return 0
