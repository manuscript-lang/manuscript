interface Value[T]:
    fn read() T

type Box[T]:
    value: T

impl Value[T] for Box[T]:
    fn read() T:
        return self.value

impl Box[T]:
    fn pick[U](other: U) U:
        return other

type Bounded[T: Equal]:
    value: T

impl Bounded[T]:
    fn read() T:
        return self.value

fn exercise(x: Box[Int], y: Box[String], z: Bounded[Int]) Int:
    let a = x.read()
    let b = y.read()
    let c = x.pick[String](b)
    return a + z.read() + c.length()
