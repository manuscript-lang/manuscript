interface Read:
    fn read() Int

type Box[T]:
    value: T

fn Box[fn(Int) Int].read() Int: 1

fn Box[fn(var Int) Int].read() Int: 2

fn identity(value: Int) Int: value
fn increment(var value: Int) Int:
    value += 1
    return value

fn exercise() Int:
    plain := Box[fn(Int) Int](identity)
    changing := Box[fn(var Int) Int](increment)
    first: Read := plain
    second: Read := changing
    return plain.read() + changing.read() + first.read() + second.read()
