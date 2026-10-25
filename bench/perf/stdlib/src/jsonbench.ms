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
                    let row = tree.at(i % 5000)
                    let id = (
                        row
                        .and_then(lambda r: r.get("id"))
                        .and_then(lambda n: n.as_int())
                        .get(0)
                    )
                    let tag = (
                        row
                        .and_then(lambda r: r.get("tags"))
                        .and_then(lambda t: t.at(-1))
                        .and_then(lambda n: n.as_string())
                        .get("")
                    )
                    total += id + tag.length()

                return total
        )
