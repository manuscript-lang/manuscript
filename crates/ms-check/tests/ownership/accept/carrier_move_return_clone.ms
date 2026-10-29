import Deque from "@std/deque.ms"

type Cursor[T]:
    source: ref Deque[T]
    position: Int

impl Cursor[T]:
    var fn next() ref Optional[T]:
        let item = self.source.at(self.position)
        self.position += 1
        return item

fn cursor_of[T](d: Deque[T]) Cursor[T]:
    return Cursor(source: d, position: 0)

fn advanced(d: Deque[String]) Cursor[String]:
    var it = cursor_of(d)
    it.position = 1
    return it

fn total(d: Deque[String]) Int:
    let first = cursor_of(d)
    var it = first
    let copy = it.clone()
    var n = 0

    while true:
        if let item = it.next():
            n += item.length()
        else:
            break

    return n + copy.position
