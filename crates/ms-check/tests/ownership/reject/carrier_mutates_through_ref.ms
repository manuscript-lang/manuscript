import Deque from "@std/deque.ms"

type Cursor[T]:
    source: ref Deque[T]
    position: Int

impl Cursor[T]:
    var fn next() ref Optional[T]:
        let item = self.source.at(self.position)
        self.position += 1
        return item

impl Cursor[T]:
    var fn clear_source() Unit:
        self.source.clear()  # error: read-only view
