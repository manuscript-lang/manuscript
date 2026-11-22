// conform: tags=mutation,maps,tier-io
// conform: phase=run
// conform: origin=bug bash: `if var n = m.get(k): n += 1` dropped the write for scalar values
import stdout from "@std/io/io.ms"

fn bump(var counts: Map[String, Int], key: String) Void:
    if var n = counts.get(key):
        n += 1
    else:
        counts[key.clone()] = 1

fn main() Void:
    var m = Map[String, Int]()
    for w in ["a", "b", "a", "a"]:
        bump(m, w)

    var f = Map[String, Float]()
    f["x"] = 1.5
    if var x = f.get("x"):
        x += 1.0
    stdout().write(f"{m.get_or("a", 0)} {m.get_or("b", 0)} {f.get_or("x", 0.0)}\n").get()
