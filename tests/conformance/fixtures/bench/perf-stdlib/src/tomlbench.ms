import range from "@std/collections.ms"
import {bench} from "./harness.ms"
import {StringBuilder} from "@std/string.ms"
import {parse} from "@std/toml.ms"

fn toml_doc(count: Int) String:
    var sb = StringBuilder()
    for i in range(0, count):
        sb.append("[item{i}]\nid = {i}\nname = \"user{i}\"\ntags = [\"a\", \"b\"]\n")
    return sb.freeze()

export fn bench_toml() Unit:
    let toml = toml_doc(2000)

    bench(
        "toml.parse",
        2000,
        fn() Int:
            if parse(toml).is_ok():
                return 1

            return 0
    )
