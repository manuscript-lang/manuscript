type Row:
    name: String

fn total(rows: List[Row]) Int:
    var n = 0
    for r in rows:
        n += r.name.length()
    return n

fn first_name(r: Row?) Int:
    match r:
        some(row):
            return row.name.length()
        none:
            return 0
