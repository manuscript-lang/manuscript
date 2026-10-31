# conform: tags=control-flow,diagnostics,generics,interfaces,lists,modules,records,stdlib-cleanup,tier-stdlib
# conform: phase=check
# conform: origin=tests/e2e/counter_aggregate_test.go:16 TestCounterAggregateQueryStates
import Closeable from "@std/core.ms"

type AggregateResource:
    visits: List[Int]

impl Closeable for AggregateResource:
    var fn close() Unit!:
        self.visits.append(1)
        return ok(unit)

interface AggregateCounter:
    var fn bump(by: Int) Int
    var fn lower(by: Int) Int

type AggregateCell:
    total: Int

impl AggregateCounter for AggregateCell:
    var fn bump(by: Int) Int:
        self.total += by
        return self.total

    var fn lower(by: Int) Int:
        self.total -= by
        return self.total

fn identity[T](value: T) T: return value
