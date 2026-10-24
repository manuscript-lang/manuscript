# conform: tags=control-flow,formatter,interfaces,lists,modules,parser,records,stdlib-cleanup,stdlib-string,strings,tier-stdlib
# conform: phase=parse
# conform: origin=tests/e2e/builder_range_test.go:16 TestBuilderAndRangeQueryStates
from "@std/string.ms" import StringBuilder
from "@std/core.ms" import Closeable

type Resource:
    visits: List[Int]

impl Closeable for Resource:
    var def close() -> Unit:
        self.visits.append(1)
