import Deque from "@std/deque.ms"

type Cursor[T]:
    source: ref Deque[T]
    position: Int

impl Cursor[T]:
    var fn next() ref Optional[T]:
        let item = self.source.at(self.position)
        self.position += 1
        return item

fn take(c: Cursor[String]) Int:
    return c.position

fn f(d: Deque[String]) Int:
    let it = Cursor(source: d, position: 0)
    let other = it  # error: cannot be moved into `other`
    return other.position
