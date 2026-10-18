import range from "@std/collections.ms"
import {bench} from "./harness.ms"
import {StringBuilder} from "@std/string.ms"
import {parse, stringify, JsonValue} from "@std/json.ms"

fn json_doc(count: Int) String:
    let sb = StringBuilder()
    sb.append("[")

    for i in range(0, count):
        if i > 0: sb.append(",")
        sb.append(
            "\{\"id\":{i},\"name\":\"user{i}\",\"tags\":[\"a\",\"b\"],\"score\":{i}.5,\"ok\":true\}"
        )

    sb.append("]")
    return sb.freeze()

fn encoded_length(value: JsonValue) Int:
    if let text = stringify(value: value): return text.length()

    return 0

export fn bench_json() Unit:
    let doc = json_doc(5000)
    bench(
        "json.parse",
        5000,
        fn() Int:
            if parse(text: doc).is_ok(): return 1

            return 0
    )
    bench(
        "json.roundtrip",
        5000,
        fn() Int:
            if let v = parse(text: doc): return encoded_length(v)

            return 0
    )
