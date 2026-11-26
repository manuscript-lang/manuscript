// conform: tags=faults,formatter,generics,lists,modules,optional,parser,records,stdlib-errors,stdlib-testing,strings,testing,tier-stdlib,try-result
// conform: phase=parse
// conform: origin=tests/e2e/testdata/accept/cl-16.ms
import expect_equal, expect_false from "@std/test/test.ms"

type Input {
	names List[String?]
}

fn outcome_value(move outcome Int!Error) Int {
	return outcome.get_or(-1)
}

test "data constructor context" {
	_input := Input([null, "Ada"])
	success Int!Error := ok(3)
	failure Int!Error := error(Error("unavailable"))
	_absent Int? := null
	_nested List[List[Int]] := [[], [1]]
	expect_equal(outcome_value(success.clone()), 3)?
	expect_equal(outcome_value(failure), -1)?
}

type Box[T] {
	value T
}

type Request {
	box Box[Int?]
}

fn select[T](hold first T, second T) &T {
	return first
}

test "nested constructor arguments receive inferred context" {
	request := Request(Box(null))
	provided Int? := 3
	selected := select(Box(null), Box(provided))
	expect_false(not (selected.value == null))?
	expect_false(not (request.box.value == null))?
}
// expect-format: rewritten
// expect-formatted: import expect_equal, expect_false from "@std/test/test.ms"
// expect-formatted:
// expect-formatted: type Input {
// expect-formatted: \tnames List[String?]
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn outcome_value(move outcome Int!) Int {
// expect-formatted: \treturn outcome.get_or(-1)
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "data constructor context" {
// expect-formatted: \t_input := Input([null, "Ada"])
// expect-formatted: \tsuccess Int! := ok(3)
// expect-formatted: \tfailure Int! := error(Error("unavailable"))
// expect-formatted: \t_absent Int? := null
// expect-formatted: \t_nested List[List[Int]] := [[], [1]]
// expect-formatted: \texpect_equal(outcome_value(success.clone()), 3)?
// expect-formatted: \texpect_equal(outcome_value(failure), -1)?
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Box[T] {
// expect-formatted: \tvalue T
// expect-formatted: }
// expect-formatted:
// expect-formatted: type Request {
// expect-formatted: \tbox Box[Int?]
// expect-formatted: }
// expect-formatted:
// expect-formatted: fn select[T](hold first T, second T) &T {
// expect-formatted: \treturn first
// expect-formatted: }
// expect-formatted:
// expect-formatted: test "nested constructor arguments receive inferred context" {
// expect-formatted: \trequest := Request(Box(null))
// expect-formatted: \tprovided Int? := 3
// expect-formatted: \tselected := select(Box(null), Box(provided))
// expect-formatted: \texpect_false(not (selected.value == null))?
// expect-formatted: \texpect_false(not (request.box.value == null))?
// expect-formatted: }
