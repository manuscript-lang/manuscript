import Closeable from "@std/core.ms"
import expect_equal, expect_fault from "@std/test/test.ms"

type Cell:
    value: Int

impl Cell:
    var fn bump() Unit:
        self.value += 1

// Faults with its own message, so a test tells which fault came first.
fn later() Int:
    let empty: List[Int] = []
    return empty[3]

fn bump_int(var x: Int) Unit:
    x += 1

fn index(var calls: Int) Int:
    calls += 1
    return 0

fn argument_place() Unit:
    var grid: List[List[Int]] = []
    bump_int(var grid[0][later()])

fn assigned_place() Unit:
    var grid: List[List[Int]] = []
    grid[0][later()] = 1

fn map_place() Unit:
    var table: Map[String, List[Int]] = Map()
    table["row"][later()] = 1

fn field_place() Unit:
    var grid: List[List[Cell]] = []
    grid[0][later()].value = 1

test "the receiver of a nested var argument faults before a later index runs":
    let message = try expect_fault(argument_place)
    try expect_equal(message.contains("index 0 out of range"), true)
    try expect_equal(message.contains("index 3"), false)

test "the receiver of a nested assignment faults before a later index runs":
    let message = try expect_fault(assigned_place)
    try expect_equal(message.contains("index 0 out of range"), true)
    try expect_equal(message.contains("index 3"), false)

test "a missing map key faults before a later index runs":
    let message = try expect_fault(map_place)
    try expect_equal(message.contains("index 3"), false)

test "the receiver of a nested field assignment faults before a later index runs":
    let message = try expect_fault(field_place)
    try expect_equal(message.contains("index 0 out of range"), true)
    try expect_equal(message.contains("index 3"), false)

test "a changing source receiver selects its element once":
    var calls = 0
    var cells = [Cell(1)]
    cells[index(var calls)].bump()
    try expect_equal(calls, 1)
    try expect_equal(cells[0].value, 2)

type Door:
    id: Int

impl Closeable for Door:
    var fn close() Unit!:
        return ok(unit)

fn at(var events: List[Int]) Int:
    events.append(1)
    return 0

fn resource_argument(var events: List[Int]) Door:
    events.append(2)
    return Door(9)

test "a resource mutator selects its receiver once, before its arguments":
    var events: List[Int] = []
    var rows: List[List[Door]] = [[Door(0)]]
    rows[at(var events)].set(0, resource_argument(var events))
    try expect_equal(rows[0][0].id, 9)
    try expect_equal(events, [1, 2])

test "a map entry mutator selects its receiver once, before its arguments":
    var events: List[Int] = []
    var table: Map[String, List[Int]] = Map()
    table.add("k", [1])
    table["k"].set(at(var events), resource_argument(var events).id)
    try expect_equal(table["k"], [9])
    try expect_equal(events, [1, 2])
