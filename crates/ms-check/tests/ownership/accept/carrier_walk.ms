import Deque from "@std/deque.ms"

type Cursor[T]:
    source: ref Deque[T]
    position: Int

impl Cursor[T]:
    var fn next() T?:
        let item = self.source.at(self.position)
        self.position += 1
        return item

fn cursor_of[T](d: Deque[T]) Cursor[T]:
    return Cursor(source: d, position: 0)

fn total(d: Deque[String]) Int:
    var it = cursor_of(d)
    var n = 0

    while true:
        if let item = it.next():
            n += item.length()
        else:
            break

    return n

fn two_live(d: Deque[String]) Int:
    var it = cursor_of(d)
    var n = 0
    if let a = it.next():
        if let b = it.next():
            n = a.length() + b.length()
    return n
