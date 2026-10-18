import range from "@std/collections.ms"
import {parse, stringify, YamlValue} from "@std/yaml.ms"
import panic from "@std/faults.ms"
import {Rng, next, text, mutate} from "./support/generator.ms"

fn generated(rng: Rng, depth: Int) YamlValue:
    var choices = 6
    if depth > 2: choices = 4
    let kind = next(rng, choices)
    if kind == 0: return YamlValue.Null
    if kind == 1: return YamlValue.BoolValue(next(rng, 2) == 0)
    if kind == 2: return YamlValue.NumberValue("{next(rng, 2000) - 1000}")
    if kind == 3: return YamlValue.StringValue(text(rng))

    if kind == 4:
        let items: List[YamlValue] = []
        for item in range(0, next(rng, 4)):
            items.append(generated(rng, depth + 1))
        return YamlValue.ArrayValue(items)

    let entries: Map[String, YamlValue] = {}
    for item in range(0, next(rng, 4)):
        entries.add(text(rng), generated(rng, depth + 1))
    return YamlValue.ObjectValue(entries)

fn check_round_trip(seed: Int, original: YamlValue) Result[Unit, Error]:
    let rendered = try stringify(original)
    if (try parse(rendered)) != original: return panic(
        "seed {seed}: changed\n{rendered}"
    )

    return ok(unit)

fn check_stable(seed: Int, mutated: String, first: YamlValue) Result[Unit, Error]:
    let again = try stringify(first)
    if (try parse(again)) != first: return panic(
        "seed {seed}: reparsed value changed\n{mutated}\n---\n{again}"
    )

    return ok(unit)

test "YAML stringify then parse preserves generated documents":
    for seed in range(1, 301):
        try check_round_trip(seed, generated(Rng(seed), 0))

test "YAML parse never faults on mutated documents and accepted input is stable":
    var accepted = 0

    for seed in range(1, 301):
        let rng = Rng(seed)
        let rendered = generated(rng, 0) | stringify | try

        for round in range(0, 4):
            let mutated = mutate(rng, rendered)

            if let first = parse(mutated):
                accepted += 1
                try check_stable(seed, mutated, first)

    if accepted == 0: return panic("mutation never produced a valid document")
