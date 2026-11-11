import (
	expect_equal, expect_error, expect_ok from "@std/test/test.ms",

	invalid, repeats from "./lib.ms",
	measure, versions from "./workloads_measure.ms",
)

// A producer for `version` that prints "correct" unless `mode` says otherwise for `bad`. Calls are counted per version.
type Producer:
	bad: String
	mode: String
	counts: Map[String, Int]
	order: List[String]

fn var Producer.run(version: String) String!:
	count := self.counts.get_or(version, 0)
	self.counts.add(version.clone(), count + 1)
	self.order.append(version.clone())

	mine := version == self.bad
	if mine and self.mode == "failed": return invalid("{version} exited 42")
	if mine and self.mode == "failed_first_trial" and count == 1: return invalid(
		"{version} exited 42"
	)
	if mine and self.mode == "wrong": return ok("WRONG!!")
	if mine and self.mode == "wrong_first_trial" and count == 1: return ok("WRONG!!")

	return ok("correct")

fn producer(bad: String, mode: String) Producer:
	return Producer(bad, mode, Map[String, Int](), List[String]())

test "every trial rotates and retains samples":
	var p = producer("", "valid")
	measured := expect_ok(measure(3, "workload", fn v: p.run(v)))?
	expect_equal(
		p.order,
		["go", "ms", "rs", "ms", "go", "rs", "go", "rs", "ms", "rs", "ms", "go"]
	)?
	expect_equal(measured.samples.length(), 9)?
	expect_equal(measured.samples.all(fn s: s.elapsed_ns > 0), true)?
	expect_equal(measured.expected, "correct")?

test "wrong or failed warm-up and early trials are rejected for every version":
	for version in versions():
		for mode in ["wrong", "wrong_first_trial", "failed", "failed_first_trial"]:
			var p = producer(version.clone(), mode.clone())
			_cause := expect_error(measure(2, "workload", fn v: p.run(v)))?

test "invalid repeat counts are refused":
	var p = producer("", "valid")
	_zero := expect_error(measure(0, "workload", fn v: p.run(v)))?
	for text in ["0", "00", "abc", "-1"]:
		_cause := expect_error(repeats(text))?
