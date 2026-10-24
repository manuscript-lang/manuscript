# Standard-library source is not ownership checked, so its `let` bindings must copy: `Deque.pop_back`
# reads a slot, overwrites it, then returns the read, which once handed back a freed string.
from "@std/io.ms" import stdout
from "@std/deque.ms" import Deque

export def main() -> Int:
    var dq = Deque[String]()
    for i in [1, 2, 3, 4, 5, 6]:
        dq.push_back(f"a-longer-string-number-{i}")

    var out = ""

    while not dq.is_empty():
        if let r = dq.pop_back():
            out += f"{r};"
        if let r = dq.pop_front():
            out += f"{r};"

    stdout().write(f"{out}\n").get()
    return 0
