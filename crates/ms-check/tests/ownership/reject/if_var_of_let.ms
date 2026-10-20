fn f(rows: List[List[Int]]) Int:
    if var head = rows.first():  # error: not declared var
        head.append(1)
    return rows.length()
