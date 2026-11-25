// conform: tags=testing,tier-stdlib
// conform: phase=test
import (
	YamlValue, parse, stringify from "@std/data/yaml.ms",
	expect_not_equal, fail from "@std/test/test.ms",

	Rng, mutate, next, text from "./support/generator.ms",
)

fn generated(var rng Rng, depth Int) YamlValue {
	var choices = 6
	if depth > 2 { choices = 4 }

	kind := next(rng, choices)
	if kind == 0 { return YamlValue.Null }
	if kind == 1 {
		return YamlValue.BoolValue(next(rng, 2) == 0)
	}
	if kind == 2 {
		return YamlValue.NumberValue(f"{next(rng, 2000) - 1000}")
	}
	if kind == 3 { return YamlValue.StringValue(text(rng)) }

	if kind == 4 {
		var items List[YamlValue] = []
		for item in 0..next(rng, 4) {
			items.append(generated(rng, depth + 1))
		}
		return YamlValue.ArrayValue(items)
	}

	var entries Map[String, YamlValue] = {}
	for item in 0..next(rng, 4) {
		entries.add(text(rng), generated(rng, depth + 1))
	}
	return YamlValue.ObjectValue(entries)
}

fn check_round_trip(seed Int, original YamlValue) Void! {
	rendered := stringify(original)?
	if (parse(rendered)?) != original { return fail(f"seed {seed}: changed\n{rendered}") }
}

fn check_stable(seed Int, mutated String, first YamlValue) Void! {
	again := stringify(first)?
	if (parse(again)?) != first {
		return fail(f"seed {seed}: reparsed value changed\n{mutated}\n---\n{again}")
	}
}

test "YAML stringify then parse preserves generated documents" {
	for seed in 1..301 {
		var rng = Rng(seed)
		check_round_trip(seed, generated(rng, 0))?
	}
}

test "YAML parse never faults on mutated documents and accepted input is stable" {
	var accepted = 0

	for seed in 1..301 {
		var rng = Rng(seed)
		rendered := generated(rng, 0) | stringify?

		for round in 0..4 {
			mutated := mutate(rng, rendered)

			if first := parse(mutated) {
				accepted += 1
				check_stable(seed, mutated, first)?
			}
		}
	}

	expect_not_equal(accepted, 0)?
}
