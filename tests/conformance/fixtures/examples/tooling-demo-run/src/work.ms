import range from "@std/collections.ms"

fn compute() Int:
    var result = 0
    for index in range(0, 3000000):
        result += index % 7
    return result

fn compare() Int:
    let left = compute()
    let right = compute()
    if left != right:
        return 1

    return 0

export fn main() Int:
    return compare()
