import {expect_contains, expect_equal, expect_fault} from "@std/testing.ms"

interface Counter:
    fn bump(by: Int) Int
    fn lower(by: Int) Int

type Cell:
    total: Int

impl Counter for Cell:
    fn bump(by: Int) Int:
        self.total += by
        return self.total

    fn lower(by: Int) Int:
        self.total -= by
        return self.total

fn sum() Int:
    let cell = Cell(0)
    var i = 0

    while i < 1000:
        cell.bump(2)
        cell.lower(1)
        i += 1

    return cell.total

fn prefix() Int:
    let cell = Cell(9223372036854775807)
    var i = 0

    while i < 2:
        cell.bump(1)
        cell.lower(1)
        i += 1

    return cell.total

fn peer() Int:
    let cell = Cell(9223372036854775807)
    let other = Cell(0)
    var i = 0

    while i < 2:
        cell.bump(other.total)
        other.bump(1)
        i += 1

    return cell.total

fn scalar_peer() Int:
    let cell = Cell(9223372036854775807)
    var sum = 0
    var i = 0

    while i < 2:
        cell.bump(sum)
        sum += 1
        i += 1

    return cell.total

fn alias() Int:
    let cell = Cell(0)
    let other = cell
    var i = 0

    while i < 2:
        other.total = 9223372036854775807
        cell.bump(1)
        i += 1

    return cell.total

fn effect(visits: List[Int]) Int:
    visits.append(7)
    return 1

fn eager(visits: List[Int]) Int:
    let cell = Cell(0)
    cell.bump(effect(visits))
    return cell.total

test "closed cell updates preserve each operation":
    sum() | try expect_equal(expected: 1000)

test "closed cells retain prefix overflow":
    (try expect_fault(fn(): let ignored = prefix())) | try expect_contains(
        expected: "Int overflow"
    )

test "peer cells and scalar carries are not initial invariants":
    (try expect_fault(fn(): let ignored = peer())) | try expect_contains(
        expected: "Int overflow"
    )
    (try expect_fault(fn(): let ignored = scalar_peer())) | try expect_contains(
        expected: "Int overflow"
    )

test "record aliases keep ordinary shared mutation":
    (try expect_fault(fn(): let ignored = alias())) | try expect_contains(
        expected: "Int overflow"
    )

test "record arguments execute exactly once before the update":
    let visits: List[Int] = []
    eager(visits) | try expect_equal(expected: 1)
    visits | try expect_equal(expected: [7])
