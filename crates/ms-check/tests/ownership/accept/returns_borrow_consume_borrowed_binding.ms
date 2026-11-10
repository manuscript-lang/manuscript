fn keep(xs: List[Int]) List[Int]:
    return xs

fn f(rows: List[List[Int]]) List[Int]:
    head := rows[0]
    return keep(head)
