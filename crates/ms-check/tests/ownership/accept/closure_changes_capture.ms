def main() -> Int:
    var total = 0
    let add = lambda (x: Int) -> Unit:
        total += x
    add(1)
    return total
