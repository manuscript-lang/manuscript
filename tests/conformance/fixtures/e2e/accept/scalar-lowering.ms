// conform: tags=testing,tier-io
// conform: phase=test
import (
	Closeable from "@std/core.ms",
	read_file, temporary, write_file from "@std/os/fs.ms",
	expect_equal,
	expect_false,
	expect_not_equal,
	expect_ok,
	expect_true from "@std/test/test.ms",
)

type Counter:
	value: Int = 0

type Resource:
	marker: String

// Cleanup runs on the resource's own copy, so a marker file is how a caller observes
// it.
fn move Resource.close() Void!:
	_written := write_file(self.marker, "closed", true).wait()

fn closed(marker: String) Bool: read_file(marker).wait().is_ok()

fn mark(var counter: Counter, digit: Int) Int:
	counter.value = counter.value * 10 + digit
	return digit

fn generic[T: Equal](left: T, right: T) Bool: left == right

fn returning_match() Bool:
	return true == match present(1):
		_value: return false
		null: false

test "primitive equality captures operands once in order":
	var counter = Counter()
	expect_not_equal(mark(counter, 1), mark(counter, 2))?
	expect_equal(counter.value, 12)?

	var original = 1
	captured := original == match present(1):
		value:
			original = 2
			value
		null: 0
	expect_false(not captured or original != 2)?

	skipped := false and mark(counter, 3) == 3
	skipped_again := true or mark(counter, 4) == 4
	expect_false((skipped or not skipped_again or counter.value != 12))?
	expect_false("é" == "e\u{0301}" or "λ🙂" != "λ🙂")?
	expect_false(not generic(left: true, right: true))?
	expect_false(returning_match())?

fn conditional(marker: String, take: Bool) Int:
	if take:
		_resource := Resource(marker.clone())
		return 7

	return 8

fn matched(marker: String) Int:
	return match present(1):
		value:
			var _resource = Resource(marker.clone())
			return value
			0
		null: 0

fn defaulted(
	marker: String,
	value: Int = match present(2):
		number:
			var _resource = Resource(marker.clone())
			_used := void
			void _resource.close()
			number
		null: 0
) Int: value

fn nested(marker: String) Void:
	callback := fn() Void:
		_resource := Resource(marker.clone())
		return

	callback()

fn failed() Int!Error: error(Error("expected"))

fn propagate(marker: String) Int!Error:
	var _resource = Resource(marker.clone())
	value := failed()?
	return ok(value)
	return ok(0)

fn bare_propagate() Int!Error:
	value := failed()?
	return ok(value)

fn equality_propagate() Bool!Error:
	matches := (failed()?) == 0
	return ok(matches)

fn bool_failed() Bool!Error: error(Error("expected"))

fn nested_results(marker: String) Int!Error:
	child := fn() Bool!Error:
		var _resource = Resource(marker.clone())
		value := bool_failed()?
		return ok(value)
		return ok(false)

	_ignored := child()
	value := failed()?
	return ok(value)

fn statement_match_try(marker: String) Int!Error:
	match present(1):
		_value:
			_resource := Resource(marker.clone())
			value := failed()?
			return ok(value)
		null: return ok(0)

	return ok(-1)

fn value_match_loop_try(marker: String) Int!Error:
	var index = 0

	while index < 2:
		_selected := match present(index):
			number:
				var _resource = Resource(marker.clone())
				_value := failed()?
				void _resource.close()
				number
			null: 0

		index += 1

	return ok(index)

test "combined lowering retains callable state and try boundaries":
	temporary := temporary("manuscript-scalar-") | expect_ok?
	dir := temporary.path()
	expected := Result[Int, Error].error(Error("expected"))
	expect_equal(nested_results(f"{dir}/nested"), expected)?
	expect_true(closed(f"{dir}/nested"))?
	expect_equal(statement_match_try(f"{dir}/statement"), expected)?
	expect_true(closed(f"{dir}/statement"))?
	expect_equal(value_match_loop_try(f"{dir}/loop"), expected)?
	expect_true(closed(f"{dir}/loop"))?

test "cleanup remains owned by its source callable":
	temporary := temporary("manuscript-scalar-") | expect_ok?
	dir := temporary.path()
	expect_equal(conditional(f"{dir}/skipped", take: false), 8)?
	expect_false(closed(f"{dir}/skipped"))?
	expect_equal(conditional(f"{dir}/taken", take: true), 7)?
	expect_true(closed(f"{dir}/taken"))?
	expect_equal(matched(f"{dir}/matched"), 1)?
	expect_true(closed(f"{dir}/matched"))?
	expect_equal(defaulted(f"{dir}/default"), 2)?
	expect_true(closed(f"{dir}/default"))?
	expect_equal(defaulted(f"{dir}/supplied", 9), 9)?
	expect_false(closed(f"{dir}/supplied"))?
	nested(f"{dir}/nested")
	expect_true(closed(f"{dir}/nested"))?
	expect_equal(
		propagate(f"{dir}/propagated"),
		Result[Int, Error].error(Error("expected")),
	)?
	expect_true(closed(f"{dir}/propagated"))?
	expect_equal(bare_propagate(), Result[Int, Error].error(Error("expected")))?
	expect_equal(equality_propagate(), Result[Bool, Error].error(Error("expected")))?

	var index = 0

	while index < 3:
		index += 1

		_resource := Resource(f"{dir}/loop{index}")
		if index == 1: continue
		if index == 2: break

	expect_true(closed(f"{dir}/loop1"))?
	expect_true(closed(f"{dir}/loop2"))?
	expect_false(closed(f"{dir}/loop3"))?

fn present[T](value: T) T?:
	return value
