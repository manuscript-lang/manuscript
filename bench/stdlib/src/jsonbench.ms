import {bench} from "./harness.ms"
import {StringBuilder} from "@std/string.ms"
import {parse, stringify, JsonValue} from "@std/json.ms"

fn json_doc(count: Int) -> String:
    let sb = StringBuilder()
    sb.append("[")
    var i = 0

    while i < count:
        if i > 0: sb.append(",")

        sb.append(
            "\{\"id\":{i},\"name\":\"user{i}\",\"tags\":[\"a\",\"b\"],\"score\":{i}.5,\"ok\":true\}"
        )
        i = i + 1

    sb.append("]")
    return sb.freeze()

fn encoded_length(value: JsonValue) -> Int:
    match stringify(value: value):
        ok(text): return text.length()
        error(_): return 0

export fn bench_json() -> Unit:
    let doc = json_doc(5000)
    bench(
        "json.parse",
        5000,
        fn() -> Int:
            match parse(text: doc):
                ok(_): return 1
                error(_): return 0
    )
    bench(
        "json.roundtrip",
        5000,
        fn() -> Int:
            match parse(text: doc):
                ok(v): return encoded_length(v)
                error(_): return 0
    )
