// Standard-library source is not ownership checked, so its `let` bindings must copy: `Deque.pop_back`
// reads a slot, overwrites it, then returns the read, which once handed back a freed string.
import Deque from "@std/collections/deque.ms"

fn main() Unit:
    var dq = Deque[String]()
    for i in [1, 2, 3, 4, 5, 6]:
        dq.push_back("a-longer-string-number-{i}")

    var out = ""

    while not dq.is_empty():
        if r := dq.pop_back():
            out += "{r};"
        if r := dq.pop_front():
            out += "{r};"

    print("{out}")
