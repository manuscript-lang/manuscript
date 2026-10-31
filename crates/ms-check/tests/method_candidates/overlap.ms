interface Value[T]:
    fn read() T

type Box[T]:
    value: T

impl Value[T] for Box[T]:
    fn read() T:
        return self.value

impl Value[Int] for Box[Int]:
    fn read() Int:
        return self.value
