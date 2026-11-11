interface Read:
    fn read() Int

type Box[T]:
    value: T

impl Read for Box[fn(Int) Int]:
    fn read() Int: 1

impl Read for Box[fn(var Int) Int]:
    fn read() Int: 2

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
