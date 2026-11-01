# conform: tags=mutation,maps,lists,tier-io
# conform: phase=run
# conform: origin=issues 2164 and 2168
import stdout from "@std/io/io.ms"

export fn main() Int:
    var m = Map[String, List[Int]]()
    m.add("a", List[Int]())
    # `if var` over `map.get(key)` changes the entry in place.
    if var q = m.get("a"): q.append(1)
    if var q = m.get("a"):
        q.append(2)
        q.append(3)
    if var q = m.get("missing"): q.append(9)
    stdout().write("{m.get("a").get([]).length()} {m.length()}\n").get()
    # A `var` of a primitive element copies it.
    var xs = [1, 2, 3]
    var y = xs[0]
    y += 10
    stdout().write("{xs[0]} {y}\n").get()
    # A `let` of a record borrows it; the record stays usable.
    let p = [7, 8]
    let alias = p
    stdout().write("{alias.length()} {p.length()}\n").get()
    return 0
