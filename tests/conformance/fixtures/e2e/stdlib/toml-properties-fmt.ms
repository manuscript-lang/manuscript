# conform: tags=aliasing,control-flow,formatter,generics,interpolation,lists,maps,modules,mutation,numbers,parser,stdlib-collections,stdlib-testing,stdlib-toml,strings,testing,tier-stdlib,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/stdlib/toml-properties.ms
import expect_not_equal, fail from "@std/test/test.ms"
import parse, stringify, TomlValue from "@std/data/toml.ms"
import Rng, next, text, mutate from "./support/generator.ms"

fn generated(var rng: Rng, depth: Int) TomlValue:
    var choices = 7
    if depth > 2: choices = 4

    let kind = next(var rng, choices)
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
    let rendered = try stringify(original)
    if (try parse(rendered)) != original: return fail(
        "seed {seed}: changed\n{rendered}"
    )

    return ok(unit)

fn check_stable(seed: Int, mutated: String, first: TomlValue) Unit!:
    let again = try stringify(first)
    if (try parse(again)) != first: return fail(
        "seed {seed}: reparsed value changed\n{mutated}\n---\n{again}"
    )

    return ok(unit)

test "TOML stringify then parse preserves generated documents":
    for seed in 1..301:
        try check_round_trip(seed, table(var Rng(seed), 0))

test "TOML parse never faults on mutated documents and accepted input is stable":
    var accepted = 0

    for seed in 1..301:
        var rng = Rng(seed)
        let rendered = table(var rng, 0) | stringify | try

        for round in 0..4:
            let mutated = mutate(var rng, rendered)

            if let first = parse(mutated):
                accepted += 1
                try check_stable(seed, mutated, first)

    try expect_not_equal(accepted, 0)
