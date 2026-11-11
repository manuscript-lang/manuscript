import (
	TomlValue, parse, stringify from "@std/data/toml.ms",
	expect_not_equal, fail from "@std/test/test.ms",

	Rng, mutate, next, text from "./support/generator.ms",
)

fn generated(var rng: Rng, depth: Int) TomlValue:
	var choices = 7
	if depth > 2: choices = 4

	kind := next(var rng, choices)
	if kind == 0: return TomlValue.BoolValue(next(var rng, 2) == 0)
	if kind == 1: return TomlValue.IntValue(next(var rng, 200000) - 100000)
	if kind == 2: return TomlValue.FloatValue(
		(next(var rng, 2000) - 1000).to_float() / 8.0
	)
	if kind == 3: return TomlValue.StringValue(text(var rng))

	if kind == 4:
		var items: List[TomlValue] = []
		for item in 0..next(var rng, 4):
			items.append(generated(var rng, depth + 1))
		return TomlValue.ArrayValue(items)

	return table(var rng, depth + 1)

fn table(var rng: Rng, depth: Int) TomlValue:
	var entries: Map[String, TomlValue] = {}
	for item in 0..next(var rng, 4):
		entries.add(text(var rng), generated(var rng, depth))
	return TomlValue.TableValue(entries)

fn check_round_trip(seed: Int, original: TomlValue) Unit!:
	rendered := stringify(original)?
	if (parse(rendered)?) != original: return fail("seed {seed}: changed\n{rendered}")

fn check_stable(seed: Int, mutated: String, first: TomlValue) Unit!:
	again := stringify(first)?
	if (parse(again)?) != first: return fail(
		"seed {seed}: reparsed value changed\n{mutated}\n---\n{again}"
	)

test "TOML stringify then parse preserves generated documents":
	for seed in 1..301:
		var rng = Rng(seed)
		check_round_trip(seed, table(var rng, 0))?

test "TOML parse never faults on mutated documents and accepted input is stable":
	var accepted = 0

	for seed in 1..301:
		var rng = Rng(seed)
		rendered := table(var rng, 0) | stringify?

		for round in 0..4:
			mutated := mutate(var rng, rendered)

			if first := parse(mutated):
				accepted += 1
				check_stable(seed, mutated, first)?

	expect_not_equal(accepted, 0)?
