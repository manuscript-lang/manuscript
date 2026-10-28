interface Value[T]:
    def read() -> T

type Box[T]:
    value: T

impl Value[T] for Box[T]:
    def read() -> T:
        return self.value

impl Box[T]:
    def pick[U](other: U) -> U:
        return other

type Bounded[T: Equal]:
    value: T

impl Bounded[T]:
    def read() -> T:
        return self.value

def exercise(x: Box[Int], y: Box[String], z: Bounded[Int]) -> Int:
    let a = x.read()
    let b = y.read()
    let c = x.pick[String](b)
    return a + z.read() + c.length()
