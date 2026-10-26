# conform: tags=generics,records,tier-stdlib
# conform: phase=run
from "@std/io.ms" import stdout

type Point:
    x: Int
    y: Int

type Box[T]:
    items: List[T]

impl Point:
    def with_x(x: Int) -> Self:
        return Point(x: x, y: self.y)

impl Box[T]:
    def added(item: T) -> Self:
        var xs = self.items.clone()
        xs.append(item)
        let b: Self = Box[T](items: xs)
        return b

    def pair(other: Self) -> List[Self]:
        return [self.clone(), other.clone()]

export def main() -> Int:
    let p = Point(x: 1, y: 2).with_x(5)
    let b = Box[Int](items: [1]).added(2)
    stdout().write(p.x.to_string() + " " + b.items.length().to_string() + " " + b.pair(b).length().to_string() + "\n")
    return 0
