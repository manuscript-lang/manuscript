interface Value[T: Equal]:
    fn read() T

type Box[T]:
    value: T

impl Value[T] for Box[T]:
    fn read() T:
        return self.value

fn exercise(x: Box[fn(Int) Int]) Int:
    let f = x.read()
    return f(1)
