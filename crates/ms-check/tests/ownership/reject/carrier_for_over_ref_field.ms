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
    let first = Cursor(source: d, position: 0)
    var n = 0

    for item in first.source:
        d = Deque[String]()  # error: borrows it
        n += item.length()

    return n
