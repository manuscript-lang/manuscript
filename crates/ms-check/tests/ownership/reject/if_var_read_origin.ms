def f(var rows: List[List[Int]]) -> Int:
    if var head = rows.first():
        head.append(rows.length())  # error: cannot use `rows`
    return rows.length()
