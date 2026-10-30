import Deque from "@std/deque.ms"

type Cursor[T]:
    source: ref Deque[T]
    position: Int

impl Cursor[T]:
    var fn next() ref T?:
        let item = self.source.at(self.position)
        self.position += 1
        return item

fn advance(var it: Cursor[String]) ref String?:
    return it.next()

fn f(var d: Deque[String]) Int:
    var it = Cursor(source: d, position: 0)
    let item = advance(var it)
    d = Deque[String]()  # error: while `item` borrows it
    if let s = item:
        return s.length()

    return 0
