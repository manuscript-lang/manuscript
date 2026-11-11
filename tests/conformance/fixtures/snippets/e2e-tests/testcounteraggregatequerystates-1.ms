// conform: tags=control-flow,diagnostics,generics,interfaces,lists,modules,records,stdlib-cleanup,tier-stdlib
// conform: phase=check
// conform: origin=tests/e2e/counter_aggregate_test.go:16 TestCounterAggregateQueryStates
import Closeable from "@std/core.ms"

type AggregateResource:
    visits: List[Int]

fn var AggregateResource.close() Unit!:
    self.visits.append(1)

interface AggregateCounter:
    var fn bump(by: Int) Int
    var fn lower(by: Int) Int

type AggregateCell:
    total: Int

fn var AggregateCell.bump(by: Int) Int:
    self.total += by
    return self.total

fn var AggregateCell.lower(by: Int) Int:
    self.total -= by
    return self.total

fn identity[T](value: T) T: return value
