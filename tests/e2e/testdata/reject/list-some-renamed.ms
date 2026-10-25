export def main() -> Int:
    let xs = [1, 2, 3]
    if xs.some(lambda (x: Int) -> Bool: x > 2):
        return 1
    return 0
