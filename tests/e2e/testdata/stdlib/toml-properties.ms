import range from "@std/collections.ms"
import {parse, stringify, TomlValue} from "@std/toml.ms"
import panic from "@std/faults.ms"
import {Rng, next, text, mutate} from "./support/generator.ms"

fn generated(rng: Rng, depth: Int) TomlValue:
    var choices = 7
    if depth > 2: choices = 4
    let kind = next(rng, choices)
    if kind == 0: return TomlValue.BoolValue(next(rng, 2) == 0)
    if kind == 1: return TomlValue.IntValue(next(rng, 200000) - 100000)
    if kind == 2: return TomlValue.FloatValue((next(rng, 2000) - 1000).to_float() / 8.0)
    if kind == 3: return TomlValue.StringValue(text(rng))

    if kind == 4:
        let items: List[TomlValue] = []
        for item in range(0, next(rng, 4)):
            items.append(generated(rng, depth + 1))
        return TomlValue.ArrayValue(items)

    return table(rng, depth + 1)

fn table(rng: Rng, depth: Int) TomlValue:
    let entries: Map[String, TomlValue] = {}
    for item in range(0, next(rng, 4)):
        entries.add(text(rng), generated(rng, depth))
    return TomlValue.TableValue(entries)

fn check_round_trip(seed: Int, original: TomlValue) Result[Unit, Error]:
    let rendered = try stringify(original)
    if (try parse(rendered)) != original: return panic(
        "seed {seed}: changed\n{rendered}"
    )

    return ok(unit)

fn check_stable(seed: Int, mutated: String, first: TomlValue) Result[Unit, Error]:
    let again = try stringify(first)
    if (try parse(again)) != first: return panic(
        "seed {seed}: reparsed value changed\n{mutated}\n---\n{again}"
    )

    return ok(unit)

test "TOML stringify then parse preserves generated documents":
    for seed in range(1, 301):
        try check_round_trip(seed, table(Rng(seed), 0))

test "TOML parse never faults on mutated documents and accepted input is stable":
    var accepted = 0

    for seed in range(1, 301):
        let rng = Rng(seed)
        let rendered = table(rng, 0) | stringify | try

        for round in range(0, 4):
            let mutated = mutate(rng, rendered)

            if let first = parse(mutated):
                accepted += 1
                try check_stable(seed, mutated, first)

    if accepted == 0: return panic("mutation never produced a valid document")
