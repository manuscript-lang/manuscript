import (
	expect_equal from "@std/test/test.ms",

	median_interval, summarize from "./call_candidates_pairs.ms",
)

test "median intervals use binomial ranks and retain ties":
	expect_equal(median_interval([6.0, 2.0, 4.0, 1.0, 5.0, 3.0]).get(), [1.0, 6.0])?
	expect_equal(median_interval([1.0, 1.0, 1.0, 1.0, 1.0, 1.0]).get(), [1.0, 1.0])?

	var values = List[Float]()
	for value in 1..102: values.append(value.to_float())
	expect_equal(median_interval(values).get(), [41.0, 61.0])?

test "interval sample limits reject invalid ranks and underflow":
	expect_equal(median_interval([]).is_error(), true)?
	expect_equal(median_interval([1.0, 1.0, 1.0, 1.0, 1.0]).is_error(), true)?

	var values = List[Float]()
	for unused in 0..1001: values.append(1.0)
	expect_equal(median_interval(values).is_error(), true)?

fn samples() String:
	var text = "round\tlabel\tinput\twall_ns\tmax_resident_bytes\tinput_sha256\tuser_ns\tsystem_ns\n"
	for round in 1..7:
		for label in ["before", "after"]:
			text += "{round}\t{label}\tinput\t100\t0\thash\t80\t20\n"
	return text

test "paired summaries require complete consistent finite measurements":
	text := samples()
	expect_equal(summarize(text).get().contains("median_candidate_ratio=1"), true)?
	expect_equal(summarize(text, cpu: true).get().contains("median95_upper=1"), true)?
	for bad in [
		text + "1\tbefore\tinput\t100\t0\thash\t80\t20\n",
		text.replace("6\tafter\tinput\t100\t0\thash\t80\t20\n", ""),
		text.replace("6\tafter", "7\tafter"),
		text.replace("\tbefore\t", "\tunknown\t"),
		text.replace("\t100\t", "\tNaN\t"),
		text.replace("\t100\t", "\tInfinity\t"),
		text.replace("\t100\t", "\t0\t"),
		text.replace(
			"6\tafter\tinput\t100\t0\thash",
			"6\tafter\tinput\t100\t0\tchanged",
		),
	]:
		expect_equal(summarize(bad).is_error(), true)?
	expect_equal(
		summarize(text.replace("\t80\t20", "\t0\t0"), cpu: true).is_error(),
		true,
	)?
