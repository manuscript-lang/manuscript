import bench from "./harness.ms"
import parse, stringify, YamlValue from "@std/data/yaml.ms"

fn yaml_doc(count Int) String:
    var sb = ""
    for i in 0..count:
        sb += f"- id: {i}\n  name: user{i}\n  tags: [a, b]\n  ok: true\n"
    return sb

fn yaml_length(value YamlValue) Int:
    if text := stringify(value):
        return text.length()

    return 0

export fn bench_yaml() Void:
    yaml := yaml_doc(2000)

    bench(
        "yaml.parse",
        2000,
        fn() Int:
            if parse(yaml).is_ok():
                return 1

            return 0
    )

    bench(
        "yaml.roundtrip",
        2000,
        fn() Int:
            if v := parse(yaml):
                return yaml_length(v)

            return 0
    )
