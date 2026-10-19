fn grow(var rows: List[List[Int]], extra: List[Int]) Unit:
    rows.append(extra.clone())

fn f() Int:
    var rows = [[1]]
    let head = rows[0]
    grow(var rows, head)  # error: while `head` borrows it
    return rows.length()
