import {bench} from "./harness.ms"
import {StringBuilder} from "@std/string.ms"
import {parse} from "@std/toml.ms"

fn toml_doc(count: Int) -> String:
    let sb = StringBuilder()
    var i = 0

    while i < count:
        sb.append("[item{i}]\nid = {i}\nname = \"user{i}\"\ntags = [\"a\", \"b\"]\n")
        i = i + 1

    return sb.freeze()

export fn bench_toml() -> Unit:
    let toml = toml_doc(2000)
    bench(
        "toml.parse",
        2000,
        fn() -> Int:
            if parse(text: toml).is_ok(): return 1

            return 0
    )
