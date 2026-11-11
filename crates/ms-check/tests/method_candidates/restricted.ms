interface Value[T: Equal]:
    fn read() T

type Box[T]:
    value: T

fn Box[T: Equal].read() T:
    return self.value

fn exercise(x: Box[fn(Int) Int]) Int:
    f := x.read()
    return f(1)
