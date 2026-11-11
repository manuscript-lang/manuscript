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
    names := twice(["a", "b"])
    shapes: List[Shape] := [Square(2)]
    more := twice(shapes)
    return names.length() + more.length()
