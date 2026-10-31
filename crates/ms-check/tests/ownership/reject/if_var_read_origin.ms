fn f(var rows: List[List[Int]]) Int:
    if var head = rows[0]?:
        head.append(rows.length())  # error: cannot use `rows`
    return rows.length()
