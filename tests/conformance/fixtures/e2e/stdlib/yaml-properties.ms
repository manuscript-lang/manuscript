# conform: tags=aliasing,control-flow,diagnostics,interpolation,lists,maps,modules,mutation,stdlib-collections,stdlib-testing,stdlib-yaml,strings,testing,tier-stdlib,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/stdlib/yaml-properties.ms
import {expect_not_equal, fail} from "@std/testing.ms"
import range from "@std/collections.ms"
import {parse, stringify, YamlValue} from "@std/yaml.ms"
import {Rng, next, text, mutate} from "./support/generator.ms"

fn generated(var rng: Rng, depth: Int) YamlValue:
    var choices = 6
    if depth > 2: choices = 4
    let kind = next(var rng, choices)
    if kind == 0: return YamlValue.Null
    if kind == 1: return YamlValue.BoolValue(next(var rng, 2) == 0)
    if kind == 2: return YamlValue.NumberValue("{next(var rng, 2000) - 1000}")
    if kind == 3: return YamlValue.StringValue(text(var rng))

    if kind == 4:
        var items: List[YamlValue] = []
        for item in range(0, next(var rng, 4)):
            items.append(generated(var rng, depth + 1))
        return YamlValue.ArrayValue(items)

    var entries: Map[String, YamlValue] = {}
    for item in range(0, next(var rng, 4)):
        entries.add(text(var rng), generated(var rng, depth + 1))
    return YamlValue.ObjectValue(entries)

fn check_round_trip(seed: Int, original: YamlValue) Result[Unit, Error]:
    let rendered = try stringify(original)
    if (try parse(rendered)) != original: return fail(
        "seed {seed}: changed\n{rendered}"
    )

    return ok(unit)

fn check_stable(seed: Int, mutated: String, first: YamlValue) Result[Unit, Error]:
    let again = try stringify(first)
    if (try parse(again)) != first: return fail(
        "seed {seed}: reparsed value changed\n{mutated}\n---\n{again}"
    )

    return ok(unit)

test "YAML stringify then parse preserves generated documents":
    for seed in range(1, 301):
        try check_round_trip(seed, generated(var Rng(seed), 0))

test "YAML parse never faults on mutated documents and accepted input is stable":
    var accepted = 0

    for seed in range(1, 301):
        var rng = Rng(seed)
        let rendered = generated(var rng, 0) | stringify | try

        for round in range(0, 4):
            let mutated = mutate(var rng, rendered)

            if let first = parse(mutated):
                accepted += 1
                try check_stable(seed, mutated, first)

    try expect_not_equal(accepted, 0)
