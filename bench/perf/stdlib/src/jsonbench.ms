from "@std/collections.ms" import range
from "./harness.ms" import bench
from "@std/string.ms" import StringBuilder
from "@std/json.ms" import parse, stringify, JsonValue

def json_doc(count: Int) -> String:
    var sb = StringBuilder()
    sb.append("[")

    for i in range(0, count):
        if i > 0: sb.append(",")
        sb.append(
            f"\{\"id\":{i},\"name\":\"user{i}\",\"tags\":[\"a\",\"b\"],\"score\":{i}.5,\"ok\":true\}"
        )

    sb.append("]")
    return sb.freeze()

def encoded_length(value: JsonValue) -> Int:
    if let text = stringify(value):
        return text.length()

    return 0

# Reads three nested fields of one row in place, without copying any subtree.
def row_weight(tree: JsonValue, index: Int) -> Int:
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

export def bench_json() -> Unit:
    let doc = json_doc(5000)

    bench(
        "json.parse",
        5000,
        lambda () -> Int:
            if parse(doc).is_ok():
                return 1

            return 0
    )

    bench(
        "json.roundtrip",
        5000,
        lambda () -> Int:
            if let v = parse(doc):
                return encoded_length(v)

            return 0
    )

    if let tree = parse(doc):
        bench(
            "json.navigate",
            100000,
            lambda () -> Int:
                var total = 0
                for i in range(0, 100000):
                    total += row_weight(tree, i % 5000)
                return total
        )
