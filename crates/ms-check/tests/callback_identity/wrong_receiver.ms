interface Read:
    fn read() Int

type Box[T]:
    value: T

impl Read for Box[fn(var Int) Int]:
    fn read() Int: 42

fn identity(value: Int) Int: value

fn exercise() Int:
    wrapped := Box[fn(Int) Int](identity)
    return wrapped.read()
