import Deque from "@std/deque.ms"

# The loop borrows the item, so the container cannot change while it is still used.
export fn main() Int:
    var d = Deque[String]()
    d.push_back("a")

    for item in d:
        d.push_back("b")
        d.push_back(item.clone())

    return 0
