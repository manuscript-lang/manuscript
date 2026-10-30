import Deque from "@std/deque.ms"

type Cursor[T]:
    source: ref Deque[T]
    position: Int

impl Cursor[T]:
    var fn next() ref T?:
        let item = self.source.at(self.position)
        self.position += 1
        return item

fn f() Int:
    var it = Cursor(source: Deque[String](), position: 0)  # error: pass a variable, not a computed value
    return it.position
