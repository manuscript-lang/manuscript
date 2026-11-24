// Validates the shared `ms bench --json` result protocol before rendering comparisons
// (bench/perf/stdlib).
import (
	parse from "@std/data/json.ms",

	invalid from "./lib.ms",
)

export type Stats:
	operations Int
	median_ns Float
	iterations Int?
	samples Int?
	min_ns Float?
	max_ns Float?
	mean_ns Float?
	stddev_ns Float?

export type Bench:
	name String
	status String
	failure String?
	stats Stats?

type Diagnostic:
	message String

type Document:
	benches List[Bench]
	diagnostics List[Diagnostic]?

fn finite(value Float) Bool:
	return value >= 0.0 and value < 1.0e300

fn valid_optional(value Float?) Bool:
	v := value
	if v != null: return finite(v)

	return true

// The passed cases of one `ms bench --json` document, in order.
export fn read_cases(output String) List[Bench]!:
	parsed := parse[Document](output)
	if parsed.is_error(): return invalid("invalid benchmark document")

	doc := parsed.get_or(Document(List[Bench](), null))
	diagnostics := doc.diagnostics.clone() or []
	if not diagnostics.is_empty(): return invalid(
		diagnostics.map(d => d.message.clone()).join("; ")
	)

	var seen = Set[String]()

	for bench in doc.benches:
		if seen.contains(bench.name): return invalid(f"duplicate case: {bench.name}")

		seen.add(bench.name.clone())
		if bench.status != "passed": return invalid(
			f"{bench.name}: {bench.status}: {(bench.failure.clone() or "")}"
		)

		stats := (
			bench.stats.clone()
			or Stats(
				operations: 0,
				iterations: null,
				samples: null,
				median_ns: -1.0,
				min_ns: null,
				max_ns: null,
				mean_ns: null,
				stddev_ns: null,
			)
		)
		if stats.operations <= 0: return invalid(f"invalid operations: {bench.name}")
		if ((stats.iterations or 1) <= 0) or ((stats.samples or 1) <= 0):
			return invalid(f"invalid iterations or samples: {bench.name}")
		if not finite(stats.median_ns): return invalid(
			f"invalid median_ns: {bench.name}"
		)
		if not (
			valid_optional(stats.min_ns)
			and valid_optional(stats.max_ns)
			and valid_optional(stats.mean_ns)
			and valid_optional(stats.stddev_ns)
		):
			return invalid(f"invalid timing: {bench.name}")

		if (stats.min_ns != null) and (stats.max_ns != null):
			if not (
				(stats.min_ns or 0.0) <= stats.median_ns
				and stats.median_ns <= (stats.max_ns or 0.0)
			):
				return invalid(f"inconsistent timing range: {bench.name}")

	if doc.benches.is_empty(): return invalid("no cases were measured")

	return ok(doc.benches)

// Display labels: the part after `::`, or the whole name when two cases would collide.
export fn case_labels(names List[String]) Map[String, String]:
	var counts = Map[String, Int]()
	var short = Map[String, String]()

	for name in names:
		parts := name.split("::")
		s := parts.slice(1, parts.length()).get_or([]).join("::")
		label := if parts.length() > 1: s else: name.clone()
		short.add(name.clone(), label.clone())
		counts.add(label.clone(), counts.get_or(label, 0) + 1)

	var labels = Map[String, String]()
	var distinct = Set[String]()

	for name in names:
		s := short.get_or(name, "")
		labels.add(name.clone(), if counts.get_or(s, 0) == 1: s else: name.clone())
		distinct.add(labels.get_or(name, ""))

	if distinct.length() != labels.length():
		var plain = Map[String, String]()
		for name in names:
			plain.add(name.clone(), name.clone())
		return plain

	return labels
