interface Divide:
    fn divide(value: Int) Int

type Number:
    value: Int

fn Number.divide(value: Int = 1 / self.value) Int:
    return value

export fn main() Int:
    return Number(0).divide()
