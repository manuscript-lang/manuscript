import range from "@std/collections.ms"
import {parse, stringify, YamlValue} from "@std/yaml.ms"
import panic from "@std/faults.ms"
import value from "./support/results.ms"
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
        var count = next(rng, 4)

        while count > 0:
            items.append(generated(rng, depth + 1))
            count = count - 1

        return YamlValue.ArrayValue(items)

    let entries: Map[String, YamlValue] = {}
    var count = next(rng, 4)

    while count > 0:
        entries.add(text(rng), generated(rng, depth + 1))
        count = count - 1

    return YamlValue.ObjectValue(entries)

fn check_round_trip(seed: Int, original: YamlValue) Unit:
    let rendered = value(stringify(original))
    if value(parse(rendered)) != original: return panic(
        "seed {seed}: changed\n{rendered}"
    )

fn check_stable(seed: Int, mutated: String, first: YamlValue) Unit:
    let again = value(stringify(first))
    if value(parse(again)) != first: return panic(
        "seed {seed}: reparsed value changed\n{mutated}\n---\n{again}"
    )

test "YAML stringify then parse preserves generated documents":
    var seed = 1

    while seed <= 300:
        check_round_trip(seed, generated(Rng(seed), 0))
        seed = seed + 1

test "YAML parse never faults on mutated documents and accepted input is stable":
    var seed = 1
    var accepted = 0

    while seed <= 300:
        let rng = Rng(seed)
        let rendered = generated(rng, 0) | stringify | value

        for round in range(0, 4):
            let mutated = mutate(rng, rendered)

            match parse(mutated):
                error(cause): let rejected = cause.message()
                ok(first):
                    accepted = accepted + 1
                    check_stable(seed, mutated, first)

        seed = seed + 1

    if accepted == 0: return panic("mutation never produced a valid document")
