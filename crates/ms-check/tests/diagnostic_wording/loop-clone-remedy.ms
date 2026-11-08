fn first(rows: List[List[Int]]) List[Int]:
    return rows[0]

export fn main() Int:
    var rows = [[1, 2], [3, 4]]
    var total = 0
    for x in rows.get(0):
        rows = [[9]]
        total += x
    return total
