from "@std/collections.ms" import range
from "./harness.ms" import bench
from "@std/string.ms" import StringBuilder
from "@std/yaml.ms" import parse, stringify, YamlValue

def yaml_doc(count: Int) -> String:
    var sb = StringBuilder()
    for i in range(0, count):
        sb.append(f"- id: {i}\n  name: user{i}\n  tags: [a, b]\n  ok: true\n")
    return sb.freeze()

def yaml_length(value: YamlValue) -> Int:
    if let text = stringify(value):
        return text.length()

    return 0

export def bench_yaml() -> Unit:
    let yaml = yaml_doc(2000)

    bench(
        "yaml.parse",
        2000,
        lambda () -> Int:
            if parse(yaml).is_ok():
                return 1

            return 0
    )

    bench(
        "yaml.roundtrip",
        2000,
        lambda () -> Int:
            if let v = parse(yaml):
                return yaml_length(v)

            return 0
    )
