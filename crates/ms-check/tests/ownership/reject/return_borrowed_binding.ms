fn f(rows: List[List[Int]]) List[Int]:
    let head = rows[0]
    return head  # error: only borrows its value
