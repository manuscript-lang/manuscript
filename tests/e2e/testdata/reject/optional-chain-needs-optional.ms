type P:
    name: String

export fn main() Int:
    let p = P(name: "a")
    let n = p?.name
    return 0
