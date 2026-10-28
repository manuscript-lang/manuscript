import {keep, measure} from "@std/bench.ms"
import StringBuilder from "@std/string.ms"
import {parse, stringify, JsonValue} from "@std/json.ms"

fn json_doc(count: Int) String:
    var sb = StringBuilder()
    sb.append("[")

    for i in 0..count:
        if i > 0: sb.append(",")
        sb.append(
            "\{\"id\":{i},\"name\":\"user{i}\",\"tags\":[\"a\",\"b\"],\"score\":{i}.5,\"ok\":true\}"
        )

    sb.append("]")
    return sb.build()

fn encoded_length(value: JsonValue) Int:
    if let text = stringify(value):
        return text.length()

    return 0

# Reads three nested fields of one row in place, without copying any subtree.
fn row_weight(tree: JsonValue, index: Int) Int:
    if let row = tree.at(index):
        var weight = 0
        if let id = row.get("id"):
            weight += id.as_int().get(0)
        if let tags = row.get("tags"):
            if let last = tags.at(-1):
                if let tag = last.as_string():
                    weight += tag.length()
        return weight

    return 0

bench "json.parse":
    let doc = json_doc(5000)

    fn work() Result[Unit, Error]:
        if parse(doc).is_ok():
            return keep(1)

        return keep(0)

    try measure(5000, work)

bench "json.roundtrip":
    let doc = json_doc(5000)

    fn work() Result[Unit, Error]:
        if let v = parse(doc):
            return keep(encoded_length(v))

        return keep(0)

    try measure(5000, work)

bench "json.navigate":
    let doc = json_doc(5000)

    if let tree = parse(doc):
        fn work() Result[Unit, Error]:
            var total = 0
            for i in 0..100000:
                total += row_weight(tree, i % 5000)
            return keep(total)

        try measure(100000, work)
