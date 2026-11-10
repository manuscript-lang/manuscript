type Box:
    value: Int

impl Box:
    fn bump(by: Int) Int:
        return self.value + by

fn twice(x: Int) Int:
    return x * 2

export fn main() Int:
    b := Box(value: 1)
    return twice(b.bump(2))
