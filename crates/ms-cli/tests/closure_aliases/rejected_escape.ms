fn escape() fn() Unit:
    var rows = [[1]]
    var first = rows[0]
    return fn(): first.append(9)

export fn main() Int:
    return 0
