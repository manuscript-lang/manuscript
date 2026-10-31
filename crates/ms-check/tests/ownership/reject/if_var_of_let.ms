fn f(rows: List[List[Int]]) Int:
    if var head = rows[0]?:  # error: not declared var
        head.append(1)
    return rows.length()
