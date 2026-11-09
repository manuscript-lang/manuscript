let table = [1, 2, 3]
let names = {"a": 1}

fn at(i: Int) Int:
    return table[i] + names["a"]

export fn main() Int:
    return at(1)
