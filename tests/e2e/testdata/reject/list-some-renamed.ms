export fn main() Int:
    let xs = [1, 2, 3]
    if xs.some(fn(x: Int) Bool: x > 2):
        return 1

    return 0
