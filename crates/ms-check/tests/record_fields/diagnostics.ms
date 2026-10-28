type Row[T]:
    first: T
    second: Int

def wrong(row: Row[String]) -> Int:
    return row.first

def missing(row: Row[String]) -> Int:
    return row.frist

type Duplicate:
    value: Int
    value: String

def duplicate(row: Duplicate) -> Int:
    return row.value
