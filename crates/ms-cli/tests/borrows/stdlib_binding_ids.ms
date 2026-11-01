# Binding identities are unique across the standard library and the program: an `if var` borrow
# here once shared an identity with a plain `let` in `@std/collections/deque.ms` and failed to lower there.
import stdout from "@std/io/io.ms"
import Deque from "@std/collections/deque.ms"

fn say(s: String) Unit:
    stdout().write("{s}\n").get()

export fn main() Int:
    var a = "hello"
    var b = a.clone()
    var m = Map[String, String]()
    var cnt = Map[String, Int]()

    for w in ["a", "b", "a", "c", "b", "a"]:
        if var n = cnt[w]?:
            n += 1
        else:
            cnt.add(w, 1)

    var d = Deque[String]()
    for i in 0..50:
        if i % 2 == 0:
            d.push_back("b{i}")
    b += "!"
    m.add(a, b)
    say("{cnt.get("a")} {d.length()} {m.get("hello")}")
    return 0
