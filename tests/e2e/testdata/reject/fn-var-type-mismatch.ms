fn count(values: List[Int]) Int:
    return values.length()

export fn main() Int:
    // `fn(List[Int]) Int` and `fn(var List[Int]) Int` are different types.
    let change: fn(var List[Int]) Int = count
    var values = [1]
    return change(var values) - 1
