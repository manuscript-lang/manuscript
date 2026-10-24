from "@std/collections.ms" import range
from "./harness.ms" import bench
from "@std/string.ms" import StringBuilder
from "@std/toml.ms" import parse

def toml_doc(count: Int) -> String:
    var sb = StringBuilder()
    for i in range(0, count):
        sb.append(f"[item{i}]\nid = {i}\nname = \"user{i}\"\ntags = [\"a\", \"b\"]\n")
    return sb.freeze()

export def bench_toml() -> Unit:
    let toml = toml_doc(2000)

    bench(
        "toml.parse",
        2000,
        lambda () -> Int:
            if parse(toml).is_ok():
                return 1

            return 0
    )
