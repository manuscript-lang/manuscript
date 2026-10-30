import Deque from "@std/deque.ms"

type Cursor[T]:
    source: ref Deque[T]
    position: Int

impl Cursor[T]:
    var fn next() ref T?:
        let item = self.source.at(self.position)
        self.position += 1
        return item

fn f() Cursor[String]:
    var d = Deque[String]()
    return Cursor(source: d, position: 0)  # error: cannot be stored or returned from a local
