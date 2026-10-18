import range from "@std/collections.ms"
import {bench} from "./harness.ms"
import {StringBuilder} from "@std/string.ms"
import {parse, stringify, YamlValue} from "@std/yaml.ms"

fn yaml_doc(count: Int) -> String:
    let sb = StringBuilder()
    for i in range(0, count):
        sb.append("- id: {i}\n  name: user{i}\n  tags: [a, b]\n  ok: true\n")
    return sb.freeze()

fn yaml_length(value: YamlValue) -> Int:
    match stringify(value: value):
    ok(text): return text.length()
    error(_): return 0

export fn bench_yaml() -> Unit:
    let yaml = yaml_doc(2000)
    bench(
        "yaml.parse",
        2000,
        fn() -> Int:
            match parse(text: yaml):
            ok(_): return 1
            error(_): return 0
    )
    bench(
        "yaml.roundtrip",
        2000,
        fn() -> Int:
            match parse(text: yaml):
            ok(v): return yaml_length(v)
            error(_): return 0
    )
