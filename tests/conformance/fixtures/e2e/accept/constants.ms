// conform: tags=alternatives,control-flow,interpolation,lists,match,modules,mutation,optional,records,stdlib-testing,strings,testing,tier-core,try-result
// conform: phase=test
// conform: origin=tests/e2e/testdata/accept/constants.ms
import expect_equal, expect_false from "@std/test/test.ms"

LIMIT := 10
DOUBLE := LIMIT * 2
NAMES: List[String] := ["a", "b"]
GREETING := f"limit {LIMIT}"
NOTHING: Int? := null
from := 4

fn limit_plus(extra: Int) Int:
	return LIMIT + extra

test "constants stand for their initializers":
	expect_equal(DOUBLE, 20)?
	expect_equal(limit_plus(1), 11)?
	expect_equal(GREETING, "limit 10")?
	expect_false(not (NOTHING == null))?
	expect_equal(from, 4)?

test "each use starts from a fresh collection":
	var names = NAMES.clone()
	names.append("c")
	expect_false(not (names.length() == 3 and NAMES.length() == 2))?

test "a local binding shadows a constant":
	LIMIT := 3
	expect_equal(LIMIT, 3)?

enum Phase:
	Idle
	Active(count: Int)

START := Phase.Idle
NEXT: Phase := Idle

fn phase_name(phase: Phase) String:
	match phase:
		Idle:
			return "idle"
		Active(count):
			return f"active {count}"

test "a qualified payloadless case is a constant":
	expect_false(not (phase_name(START) == "idle" and phase_name(NEXT) == "idle"))?
