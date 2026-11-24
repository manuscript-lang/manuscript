// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	panic from "@std/core.ms",
	expect_contains, expect_equal, expect_fault from "@std/test/test.ms",
)

type Cell {
	value Int
}

fn var Cell.add(value Int) Void {
	self.value += value
}

fn var Cell.add_both(value Int, var other Int) Void {
	self.value += value
	other += 10
}

fn next(var calls Int) Int {
	selected := calls % 2
	calls += 1
	return selected
}

fn mark(var events List[Int], value Int) Int {
	events.append(value)
	return 0
}

fn argument(var events List[Int]) Int {
	events.append(2)
	return 9
}

fn fail(var events List[Int]) Int! {
	events.append(2)
	return error(Error("later argument"))
}

fn bump(var value Int, amount Int) Void {
	value += amount
}

fn nested_try(var rows List[List[Int]], var events List[Int]) Void! {
	rows[9].set(mark(events, 1), fail(events)?)
}

test "an earlier list fault prevents a later index" {
	var rows = [[0]]
	message := expect_fault(() => rows[9][later_fault()] = 7)?
	expect_contains(message, "out of range")?
}

test "an earlier map fault prevents a later index" {
	var rows Map[String, List[Int]] = {"present": [0]}
	message := expect_fault(() => rows["missing"][later_fault()] = 7)?
	expect_contains(message, "map key not found")?
}

test "an earlier receiver fault precedes a later try exit" {
	var rows = [[0]]
	var events List[Int] = []
	void expect_fault(() => void nested_try(rows, events))?
	expect_equal(events, [])?
}

test "a changing source receiver selects its cell once" {
	var cells = [Cell(1), Cell(20)]
	var calls = 0
	cells[next(calls)].add(5)
	expect_equal(calls, 1)?
	expect_equal(cells[0].value, 6)?
	expect_equal(cells[1].value, 20)?
}

test "a changing source receiver runs before its argument" {
	var cells = [Cell(1)]
	var events List[Int] = []
	cells[mark(events, 1)].add(argument(events))
	expect_equal(events, [1, 2])?
	expect_equal(cells[0].value, 10)?
}

test "implicit and explicit changing arguments retain their own selections" {
	var cells = [Cell(1), Cell(20)]
	var values = [3, 40]
	var receiver_calls = 0
	var argument_calls = 0
	cells[next(receiver_calls)].add_both(5, values[next(argument_calls)])
	expect_equal(receiver_calls, 1)?
	expect_equal(argument_calls, 1)?
	expect_equal(cells[0].value, 6)?
	expect_equal(cells[1].value, 20)?
	expect_equal(values, [13, 40])?
}

test "a native receiver fault precedes its argument" {
	var rows = [[0]]
	message := expect_fault(() => rows[9].append(later_fault()))?
	expect_contains(message, "out of range")?
}

test "a source receiver fault precedes its argument" {
	var cells = [Cell(1)]
	message := expect_fault(() => cells[9].add(later_fault()))?
	expect_contains(message, "out of range")?
}

interface Change {
	fn apply(var value Int, amount Int) Void
}

type Adder {
	unused Bool = false
}

fn Adder.apply(var value Int, amount Int) Void {
	value += amount
}

test "a contract var argument retains its changing index" {
	change Change := Adder()
	var values = [1, 20]
	var calls = 0
	change.apply(values[next(calls)], 5)
	expect_equal(calls, 1)?
	expect_equal(values, [6, 20])?
}

test "a function value var argument retains its changing index" {
	change fn(var Int, Int) Void := bump
	var values = [1, 20]
	var calls = 0
	change(values[next(calls)], 5)
	expect_equal(calls, 1)?
	expect_equal(values, [6, 20])?
}

fn key(var events List[Int]) String {
	events.append(2)
	return "key"
}

test "an indexed map fast path evaluates its receiver before its key" {
	var maps List[Map[String, Int]] = [{}, {}]
	var events List[Int] = []
	maps[mark(events, 1)].add(key(events), 9)
	expect_equal(events, [1, 2])?
	expect_equal(maps[0]["key"], 9)?
}

test "an indexed map fast path faults before evaluating its key" {
	var maps List[Map[String, Int]] = [{}]
	var events List[Int] = []
	void expect_fault(() => maps[9].add(key(events), 9))?
	expect_equal(events, [])?
}

fn owned_key(var calls Int) String {
	calls += 1
	return f"key{calls}"
}

test "an owned map key survives through changing receiver writeback" {
	var cells = {"key1": Cell(1), "key2": Cell(20)}
	var calls = 0
	cells[owned_key(calls)].add(5)
	expect_equal(calls, 1)?
	expect_equal(cells["key1"].value, 6)?
	expect_equal(cells["key2"].value, 20)?
}

fn choose(var values List[Int], var calls Int) Int {
	bump(values[next(calls)], 1)
	return 0
}

test "a nested mutable call inside an index keeps both selections" {
	var values = [1, 20]
	var cells = [Cell(2)]
	var calls = 0
	cells[choose(values, calls)].add(5)
	expect_equal(calls, 1)?
	expect_equal(values, [2, 20])?
	expect_equal(cells[0].value, 7)?
}

test "a nested field assignment stops at its first invalid receiver" {
	var cells = [[Cell(1)]]
	message := expect_fault(() => cells[9][later_fault()].value = 7)?
	expect_contains(message, "out of range")?
}

test "an explicit var argument stops at the first invalid receiver" {
	var rows = [[0]]
	message := expect_fault(() => bump(rows[9][later_fault()], 7))?
	expect_contains(message, "out of range")?
}

test "an implicit nested source receiver stops before its later index" {
	var cells = [[Cell(1)]]
	message := expect_fault(() => cells[9][later_fault()].add(7))?
	expect_contains(message, "out of range")?
}

test "a borrowed key fast path selects its indexed receiver first" {
	var maps List[Map[String, Int]] = [{}]
	key := "key"
	var events List[Int] = []
	maps[mark(events, 1)].add(key.clone(), argument(events))
	expect_equal(events, [1, 2])?
	expect_equal(maps[0][key], 9)?
}

test "a borrowed key fast path faults before its value argument" {
	var maps List[Map[String, Int]] = [{}]
	key := "key"
	message := expect_fault(() => maps[9].add(key.clone(), later_fault()))?
	expect_contains(message, "out of range")?
}

fn later_fault() Int {
	return panic("later selection ran")
}
