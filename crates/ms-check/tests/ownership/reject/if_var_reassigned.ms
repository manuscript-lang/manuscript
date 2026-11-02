fn f(var rows: List[List[Int]]) Int:
    if var head = rows[0]?:
        head = [9]  # error: cannot reassign
    return rows.length()
