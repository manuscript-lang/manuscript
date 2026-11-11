type P:
    name: String

export fn main() Int:
    p: P? := none
    n := p ?.name
    return 0
