import Deque from "@std/deque.ms"

type Cursor[T]:
    source: ref Deque[T]
    position: Int

impl Cursor[T]:
    var fn next() ref Optional[T]:
        let item = self.source.at(self.position)
        self.position += 1
        return item

fn f(var d: Deque[String]) Int:
    var it = Cursor(source: d, position: 0)
    it.source.size = 0  # error: read-only view
    return it.position
