interface Value[T]:
    fn read() T

type Box[T]:
    value: T

fn Box[T].read() T:
    return self.value

fn Box[T].pick[U](other: U) U:
    return other

type Bounded[T: Equal]:
    value: T

fn Bounded[T].read() T:
    return self.value

fn exercise(x: Box[Int], y: Box[String], z: Bounded[Int]) Int:
    a := x.read()
    b := y.read()
    c := x.pick[String](b)
    return a + z.read() + c.length()
