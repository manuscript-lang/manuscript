# conform: tags=mutation,maps,tier-io
# conform: phase=run
# conform: origin=bug bash: `if var n = m.get(k): n += 1` dropped the write for scalar values
import stdout from "@std/io/io.ms"

fn bump(var counts: Map[String, Int], key: String) Unit:
    if var n = counts.get(key):
        n += 1
    else:
        counts[key] = 1

export fn main() Int:
    var m = Map[String, Int]()
    for w in ["a", "b", "a", "a"]:
        bump(var m, w)
    var f = Map[String, Float]()
    f["x"] = 1.5
    if var x = f.get("x"):
        x += 1.0
    stdout().write("{m.get("a").get(0)} {m.get("b").get(0)} {f.get("x").get(0.0)}\n").get()
    return 0
