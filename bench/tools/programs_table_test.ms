import (
	expect_contains, expect_equal, expect_error from "@std/test/test.ms",

	SINK, ops, summarize from "./programs_table.ms",
)

fn sample(version: String) List[String]:
	var lines = ops().map(fn op: "{version} {op.name} {op.count} {op.count * 2}")
	lines.append("{version} # sink " + SINK.map(fn n: "{n}").join(" "))
	return lines

fn both() List[String]:
	return sample("ms").concat(sample("go"))

test "complete equivalent work":
	result := summarize(both(), 1)?
	expect_contains(result, "1.00x")?
	expect_contains(result, "Checksums and operation counts verified")?

test "extra versions add columns":
	lines := both().concat(sample("rust")).concat(sample("rust-checked"))
	result := summarize(lines, 1)?
	expect_contains(
		result,
		"| operation | ops | Manuscript | Go | Rust | Rust, overflow checks | ms / Go | ms / Rust | ms / Rust, overflow checks |",
	)?
	expect_equal(result.split("1.00x").length() - 1, 3 * ops().length())?

test "rejects invalid evidence":
	valid := both()
	last := valid.length() - 1
	var cut = valid.clone()
	cut.remove(last)

	var doubled = valid.clone()
	doubled = doubled.concat(sample("ms"))

	var short_count = valid.clone()
	short_count[0] = short_count[0].replace("50000 100000", "1 100000")

	var zero_time = valid.clone()
	zero_time[0] = zero_time[0].replace("100000", "0")

	var bad_sink = valid.clone()
	bad_sink[last] = bad_sink[last].replace("50000", "49999")

	extra_first := [valid[0].clone()].concat(valid)
	junk := ["unrecognized output"].concat(valid)
	for lines in [cut, doubled, short_count, zero_time, bad_sink, extra_first, junk]:
		_cause := expect_error(summarize(lines, 1))?
