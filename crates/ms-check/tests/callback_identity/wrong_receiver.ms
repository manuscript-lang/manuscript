interface Read:
    fn read() Int

type Box[T]:
    value: T

fn Box[fn(var Int) Int].read() Int: 42

fn identity(value: Int) Int: value

fn exercise() Int:
    wrapped := Box[fn(Int) Int](identity)
    return wrapped.read()
