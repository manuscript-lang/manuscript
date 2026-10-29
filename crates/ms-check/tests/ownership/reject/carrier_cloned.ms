import Deque from "@std/deque.ms"

type Cursor[T]:
    source: ref Deque[T]
    position: Int

impl Cursor[T]:
    var fn next() ref Optional[T]:
        let item = self.source.at(self.position)
        self.position += 1
        return item

fn f(d: Deque[String]) Int:
    let it = Cursor(source: d, position: 0)
    let c = it.clone()  # error: a copy would outlive
    return c.position
