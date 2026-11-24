// conform: tags=control-flow,formatter,interfaces,lists,modules,parser,records,stdlib-cleanup,stdlib-string,strings,tier-stdlib
// conform: phase=parse
// conform: origin=tests/e2e/builder_range_test.go:16 TestBuilderAndRangeQueryStates
import Closeable from "@std/core.ms"

type Resource:
    visits List[Int]

fn move Resource.close() Void!:
    self.visits.append(1)
