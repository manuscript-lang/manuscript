import Shared, share from "@std/concurrency/shared.ms"

interface Shape:
    fn area() Int

type Square:
    side: Int

impl Shape for Square:
    fn area() Int:
        return self.side * self.side

fn twice[T: Clonable](xs: List[T]) List[T]:
    return xs.concat(xs.reversed())

fn copies() Int:
    let fs = twice([fn(x: Int) Int: x + 1])
    let shapes: List[Shape] = [Square(2)]
    let more = twice(shapes)
    let shared = twice([share(1)])
    return fs.length() + more.length() + shared.length()
