import {keep, measure} from "@std/bench.ms"
import StringBuilder from "@std/string.ms"
import {parse, stringify, YamlValue} from "@std/yaml.ms"

fn yaml_doc(count: Int) String:
    var sb = StringBuilder()
    for i in 0..count:
        sb.append("- id: {i}\n  name: user{i}\n  tags: [a, b]\n  ok: true\n")
    return sb.build()

fn yaml_length(value: YamlValue) Int:
    if let text = stringify(value):
        return text.length()

    return 0

bench "yaml.parse":
    let yaml = yaml_doc(2000)

    fn work() Result[Unit, Error]:
        if parse(yaml).is_ok():
            return keep(1)

        return keep(0)

    try measure(2000, work)

bench "yaml.roundtrip":
    let yaml = yaml_doc(2000)

    fn work() Result[Unit, Error]:
        if let v = parse(yaml):
            return keep(yaml_length(v))

        return keep(0)

    try measure(2000, work)

bench "yaml.stringify":
    let yaml = yaml_doc(2000)
    if let v = parse(yaml):
        try measure(2000, fn: keep(yaml_length(v)))
