export def main() -> Int:
    var rows = [[1], [2]]
    var head = rows[0]
    let n = rows.length()
    head.append(n)
    return head.length()
