import {expect_not_equal, expect_ok} from "@std/testing.ms"
import TextError from "@std/errors.ms"
import range from "@std/collections.ms"
import {parse, stringify, TomlValue} from "@std/toml.ms"
import {Rng, next, text, mutate} from "./support/generator.ms"

fn generated(rng: Rng, depth: Int) -> TomlValue:
    var choices = 7
    if depth > 2: choices = 4
    let kind = next(rng, choices)
    if kind == 0: return TomlValue.BoolValue(next(rng, 2) == 0)
    if kind == 1: return TomlValue.IntValue(next(rng, 200000) - 100000)
    if kind == 2: return TomlValue.FloatValue((next(rng, 2000) - 1000).to_float() / 8.0)
    if kind == 3: return TomlValue.StringValue(text(rng))

    if kind == 4:
        let items: List[TomlValue] = []
        var count = next(rng, 4)

        while count > 0:
            items.append(generated(rng, depth + 1))
            count = count - 1

        return TomlValue.ArrayValue(items)

    return table(rng, depth + 1)

fn table(rng: Rng, depth: Int) -> TomlValue:
    let entries: Map[String, TomlValue] = {}
    var count = next(rng, 4)

    while count > 0:
        entries.add(text(rng), generated(rng, depth))
        count = count - 1

    return TomlValue.TableValue(entries)

fn check_round_trip(seed: Int, original: TomlValue) -> Result[Unit, Error]:
    let rendered = (stringify(original) | try expect_ok)
    if (parse(rendered) | try expect_ok) != original: return error(
        TextError.Text("seed {seed}: changed\n{rendered}")
    )

    return ok(unit)

fn check_stable(seed: Int, mutated: String, first: TomlValue) -> Result[Unit, Error]:
    let again = (stringify(first) | try expect_ok)
    if (parse(again) | try expect_ok) != first: return error(
        TextError.Text(
            "seed {seed}: reparsed value changed\n{mutated}\n---\n{again}"
        )
    )

    return ok(unit)

test "TOML stringify then parse preserves generated documents":
    var seed = 1

    while seed <= 300:
        (try check_round_trip(seed, table(Rng(seed), 0)))
        seed = seed + 1

test "TOML parse never faults on mutated documents and accepted input is stable":
    var seed = 1
    var accepted = 0

    while seed <= 300:
        let rng = Rng(seed)
        let rendered = table(rng, 0) | stringify | try expect_ok

        for round in range(0, 4):
            let mutated = mutate(rng, rendered)

            match parse(mutated):
                error(cause): let rejected = cause.message()
                ok(first):
                    accepted = accepted + 1
                    (try check_stable(seed, mutated, first))

        seed = seed + 1

    accepted | try expect_not_equal(expected: 0)
