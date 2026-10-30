import Deque from "@std/deque.ms"

type Cursor[T]:
    source: ref Deque[T]
    position: Int

impl Cursor[T]:
    var fn next() ref T?:
        let item = self.source.at(self.position)
        self.position += 1
        return item

fn f(var d: Deque[String]) Int:
    var it = Cursor(source: d, position: 0)
    var other = it.source  # error: read-only view
    other.clear()
    return it.position
