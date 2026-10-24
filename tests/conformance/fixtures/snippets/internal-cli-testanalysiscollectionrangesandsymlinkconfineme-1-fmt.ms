# conform: tags=formatter,modules,parser,stdlib-collections,tier-stdlib
# conform: phase=parse
# conform: origin=internal/cli/analysis_test.go:203 TestAnalysisCollectionRangesAndSymlinkConfinement
# header
from "@std/collections.ms" import ListBuilder, List

def update(items: ListBuilder[Int]) -> Int:
    return 0
