type Row[T]:
    first: T
    second: Int

fn wrong(row: Row[String]) Int:
    return row.first

fn missing(row: Row[String]) Int:
    return row.frist

type Duplicate:
    value: Int
    value: String

fn duplicate(row: Duplicate) Int:
    return row.value
