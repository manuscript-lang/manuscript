# conform: tags=control-flow,diagnostics,generics,interfaces,lists,modules,records,stdlib-cleanup,tier-stdlib
# conform: phase=check
# conform: origin=tests/e2e/counter_aggregate_test.go:16 TestCounterAggregateQueryStates
from "@std/core.ms" import Closeable

type AggregateResource:
    visits: List[Int]

impl Closeable for AggregateResource:
    var def close() -> Unit:
        self.visits.append(1)

interface AggregateCounter:
    var def bump(by: Int) -> Int
    var def lower(by: Int) -> Int

type AggregateCell:
    total: Int

impl AggregateCounter for AggregateCell:
    var def bump(by: Int) -> Int:
        self.total += by
        return self.total

    var def lower(by: Int) -> Int:
        self.total -= by
        return self.total

def identity[T](value: T) -> T: return value
