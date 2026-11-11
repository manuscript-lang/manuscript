interface Value[T]:
    fn read() T

type Box[T]:
    value: T

fn Box[T].read() T:
    return self.value

fn Box[Int].read() Int:
    return self.value
