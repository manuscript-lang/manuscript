import {bench} from "./harness.ms"
import {StringBuilder} from "@std/string.ms"
import {parse, stringify, YamlValue} from "@std/yaml.ms"

fn yaml_doc(count: Int) -> String:
    let sb = StringBuilder()
    var i = 0

    while i < count:
        sb.append("- id: {i}\n  name: user{i}\n  tags: [a, b]\n  ok: true\n")
        i = i + 1

    return sb.freeze()

fn yaml_length(value: YamlValue) -> Int:
    if let text = stringify(value: value): return text.length()

    return 0

export fn bench_yaml() -> Unit:
    let yaml = yaml_doc(2000)
    bench(
        "yaml.parse",
        2000,
        fn() -> Int:
            if parse(text: yaml).is_ok(): return 1

            return 0
    )
    bench(
        "yaml.roundtrip",
        2000,
        fn() -> Int:
            if let v = parse(text: yaml): return yaml_length(v)

            return 0
    )
