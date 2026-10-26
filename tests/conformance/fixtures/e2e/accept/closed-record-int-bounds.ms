# conform: tags=closures,control-flow,interfaces,lists,modules,mutation,records,stdlib-testing,testing,tier-core,try-result
# conform: phase=test
# conform: origin=tests/e2e/testdata/accept/closed-record-int-bounds.ms
from "@std/testing.ms" import expect_contains, expect_equal, expect_fault

interface Counter:
    var def bump(by: Int) -> Int
    var def lower(by: Int) -> Int

type Cell:
    total: Int

impl Counter for Cell:
    var def bump(by: Int) -> Int:
        self.total += by
        return self.total

    var def lower(by: Int) -> Int:
        self.total -= by
        return self.total

def sum() -> Int:
    var cell = Cell(0)
    var i = 0

    while i < 1000:
        cell.bump(2)
        cell.lower(1)
        i += 1

    return cell.total

def prefix() -> Int:
    var cell = Cell(9223372036854775807)
    var i = 0

    while i < 2:
        cell.bump(1)
        cell.lower(1)
        i += 1

    return cell.total

def peer() -> Int:
    var cell = Cell(9223372036854775807)
    var other = Cell(0)
    var i = 0

    while i < 2:
        cell.bump(other.total)
        other.bump(1)
        i += 1

    return cell.total

def scalar_peer() -> Int:
    var cell = Cell(9223372036854775807)
    var sum = 0
    var i = 0

    while i < 2:
        cell.bump(sum)
        sum += 1
        i += 1

    return cell.total

def reset() -> Int:
    var cell = Cell(0)
    var i = 0

    while i < 2:
        cell.total = 9223372036854775807
        cell.bump(1)
        i += 1

    return cell.total

def effect(var visits: List[Int]) -> Int:
    visits.append(7)
    return 1

def eager(var visits: List[Int]) -> Int:
    var cell = Cell(0)
    cell.bump(effect(var visits))
    return cell.total

test "closed cell updates preserve each operation":
    sum() | try expect_equal(1000)

test "closed cells retain prefix overflow":
    (try expect_fault(lambda: let _ignored = prefix())) | try expect_contains(
        "Int overflow"
    )

test "peer cells and scalar carries are not initial invariants":
    (try expect_fault(lambda: let _ignored = peer())) | try expect_contains(
        "Int overflow"
    )
    (try expect_fault(lambda: let _ignored = scalar_peer())) | try expect_contains(
        "Int overflow"
    )

test "field resets keep ordinary overflow checks":
    (try expect_fault(lambda: let _ignored = reset())) | try expect_contains(
        "Int overflow"
    )

test "record arguments execute exactly once before the update":
    var visits: List[Int] = []
    eager(var visits) | try expect_equal(1)
    visits | try expect_equal([7])
