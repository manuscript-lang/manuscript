import range from "@std/collections.ms"
import {bench} from "./harness.ms"
import {StringBuilder} from "@std/string.ms"
import {parse} from "@std/toml.ms"

fn toml_doc(count: Int) -> String:
    let sb = StringBuilder()
    for i in range(0, count):
        sb.append("[item{i}]\nid = {i}\nname = \"user{i}\"\ntags = [\"a\", \"b\"]\n")
    return sb.freeze()

export fn bench_toml() -> Unit:
    let toml = toml_doc(2000)
    bench(
        "toml.parse",
        2000,
        fn() -> Int:
            match parse(text: toml):
                ok(_): return 1
                error(_): return 0
    )
