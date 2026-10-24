# conform: tags=diagnostics,modules,stdlib-collections,tier-stdlib
# conform: phase=check
# conform: origin=internal/cli/analysis_test.go:203 TestAnalysisCollectionRangesAndSymlinkConfinement
# header
from "@std/collections.ms" import ListBuilder, List

def update(items: ListBuilder[Int]) -> Int:
    return 0
