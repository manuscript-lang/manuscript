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

    if let item = it.next():
        d.push_back("x")  # error: while `item` borrows it
        return item.length()

    return 0
