type Row:
    name: String

def total(rows: List[Row]) -> Int:
    var n = 0
    for ref r in rows:
        n += r.name.length()
    return n

def first_name(r: Optional[Row]) -> Int:
    match ref r:
        case some(row):
            return row.name.length()
        case none:
            return 0
