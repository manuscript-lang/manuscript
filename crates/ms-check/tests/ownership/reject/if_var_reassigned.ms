def f(var rows: List[List[Int]]) -> Int:
    if var head = rows.first():
        head = [9]  # error: cannot reassign
    return rows.length()
