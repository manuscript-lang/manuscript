interface Value[T: Equal]:
    def read() -> T

type Box[T]:
    value: T

impl Value[T] for Box[T]:
    def read() -> T:
        return self.value

def exercise(x: Box[Callable[[Int], Int]]) -> Int:
    let f = x.read()
    return f(1)
