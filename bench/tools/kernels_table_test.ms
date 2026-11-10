import (
	ablations,
	base_versions,
	c_versions,
	omitted,
	suite_names,
	summarize from "./kernels_table.ms",
	must, Ran from "./lib.ms",
	expect_contains, expect_equal, expect_error, expect_ok from "@std/test/test.ms",
)

fn trial(version: String, suite: String, micros: Int) List[String]:
	names := suite_names(suite).filter(fn n: not omitted(version).contains(n))
	var lines = names.map(fn name: "{version} {name} {micros} 1")
	lines.append("{version} # end")
	return lines

fn trials(versions: List[String], suite: String, micros: Int) List[String]:
	var lines = List[String]()
	for v in versions:
		lines = lines.concat(trial(v, suite, micros))
	return lines

fn kernel_versions() List[String]:
	return base_versions().concat(c_versions())

test "complete rotating trials preserve minimum and columns":
	for suite in ["kernels", "competence"]:
		versions := if suite == "kernels": kernel_versions() else: base_versions()
		var rotated = versions.slice(1, versions.length()).get([])
		rotated.append(versions[0].clone())

		lines := trials(versions, suite, 100).concat(trials(rotated, suite, 50))
		report := try expect_ok(summarize(lines, suite, 2, versions))
		try expect_contains(report, "Minimum of 2 rotating runs")
		try expect_contains(report, "| ms / rust | ms / rust-checked |")
		try expect_contains(report, "| {suite_names(suite)[0]} | 50 | 50 | 1.00x")

test "ablation versions and folded times":
	versions := kernel_versions().concat(ablations())
	report := try expect_ok(
		summarize(trials(versions, "kernels", 0), "kernels", 1, versions)
	)
	try expect_contains(report, "c-ms-unchecked us")
	try expect_contains(report, "folded")

test "plain C omits map_count and reports n/a":
	versions := kernel_versions()
	report := try expect_ok(
		summarize(trials(versions, "kernels", 100), "kernels", 1, versions)
	)
	try expect_contains(
		report,
		"| map_count_2M | 100 | 100 | 1.00x | 100 | 1.00x | 100 | 1.00x | n/a | n/a |"
	)

	with_map := trials(versions, "kernels", 100).concat(["c map_count_2M 100 1"])
	_extra := try expect_error(summarize(with_map, "kernels", 1, versions))

test "rejects invalid evidence":
	versions := kernel_versions()
	good := trials(versions, "kernels", 100)
	omitted := suite_names("kernels")[0]
	last := good.length() - 1
	var truncated = good.clone()
	truncated.remove(last)

	var no_omitted = good.filter(fn l: not l.contains(omitted))
	var no_c = good.filter(fn l: not l.starts_with("c "))
	var cases = [
		List[String](),
		truncated,
		good.concat(trial("ms", "kernels", 100)),
		no_omitted,
		good.slice(1, good.length()).get([]),
		[good[0].clone()].concat(good),
		no_c,
		[good[0].replace("100", "-1")].concat(
			good.slice(1, good.length()).get([])
		),
		[good[0].replace("100", "nan")].concat(
			good.slice(1, good.length()).get([])
		),
		[good[0].replace(" 1", " 2")].concat(
			good.slice(1, good.length()).get([])
		),
		[good[0].replace(omitted, "unknown")].concat(
			good.slice(1, good.length()).get([])
		),
		[good[0].replace("go ", "unknown ")].concat(
			good.slice(1, good.length()).get([])
		),
		["go # end"].concat(good),
		good.concat(["unrecognized output"])
	]
	for lines in cases:
		_cause := try expect_error(summarize(lines, "kernels", 1, versions))

	_zero := try expect_error(summarize(good, "kernels", 0, versions))
	_short := try expect_error(summarize(good, "kernels", 1, base_versions()))

test "a late checksum mismatch produces no report":
	var lines = trials(kernel_versions(), "kernels", 100)
	lines[lines.length() - 2] = lines[lines.length() - 2].replace(" 1", " 2")

	cause := try expect_error(summarize(lines, "kernels", 1, kernel_versions()))
	try expect_contains(cause.message, "checksums differ")

test "a producer that fails or prints nothing is rejected":
	failed := Ran(true, 42, "", "boom")
	_failure := try expect_error(must("producer", failed))
	missing := Ran(false, 125, "", "cannot start")
	_start := try expect_error(must("producer", missing))
	fine := Ran(true, 0, "ok", "")
	try expect_equal(try expect_ok(must("producer", fine)), "ok")

	versions := kernel_versions()
	empty := trials(versions.slice(0, 5).get([]), "kernels", 100)
	_empty := try expect_error(summarize(empty, "kernels", 1, versions))
