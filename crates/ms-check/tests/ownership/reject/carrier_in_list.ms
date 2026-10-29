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
    var its: List[Cursor[String]] = []  # error: a collection cannot do
    let it = Cursor(source: d, position: 0)
    its.append(it)  # error: holds a borrow
    return its.length()
