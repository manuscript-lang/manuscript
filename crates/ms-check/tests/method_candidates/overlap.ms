interface Value[T]:
    def read() -> T

type Box[T]:
    value: T

impl Value[T] for Box[T]:
    def read() -> T:
        return self.value

impl Value[Int] for Box[Int]:
    def read() -> Int:
        return self.value
