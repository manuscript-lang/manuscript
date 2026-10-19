# conform: tags=control-flow,diagnostics,generics,interfaces,lists,modules,records,stdlib-cleanup,tier-stdlib
# conform: phase=check
# conform: origin=tests/e2e/counter_aggregate_test.go:16 TestCounterAggregateQueryStates
import Closeable from "@std/cleanup.ms"
type AggregateResource:
    visits: List[Int]
impl Closeable for AggregateResource:
    fn close() Unit:
        self.visits.append(1)
interface AggregateCounter:
    fn bump(by: Int) Int
    fn lower(by: Int) Int
type AggregateCell:
    total: Int
impl AggregateCounter for AggregateCell:
    fn bump(by: Int) Int:
        self.total += by
        return self.total
    fn lower(by: Int) Int:
        self.total -= by
        return self.total
fn identity[T](value: T) T: return value
