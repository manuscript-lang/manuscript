# Binding identities are unique across the standard library and the program: an `if var` borrow
# here once shared an identity with a plain `let` in `@std/deque.ms` and failed to lower there.
from "@std/io.ms" import stdout
from "@std/deque.ms" import Deque
from "@std/collections.ms" import range

def say(s: String) -> Unit:
    stdout().write(f"{s}\n").get()

export def main() -> Int:
    var a = "hello"
    var b = a.clone()
    var m = Map[String, String]()
    var cnt = Map[String, Int]()

    for w in ["a", "b", "a", "c", "b", "a"]:
        if var n = cnt.get(w):
            n += 1
        else:
            cnt.add(w, 1)

    var d = Deque[String]()
    for i in range(0, 50):
        if i % 2 == 0:
            d.push_back(f"b{i}")
    b += "!"
    m.add(a, b)
    say(f"{cnt.get("a")} {d.length()} {m.get("hello")}")
    return 0
