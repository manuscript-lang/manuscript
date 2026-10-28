type Box[T]:
    value: T

type Row[A, B]:
    first: A
    middle: List[B]
    last: Callable[[A], B]
    nested: Box[Optional[B]]
    to_string: Int

impl Row[A, B]:
    def count() -> Int:
        return 1

def first(row: Row[Int, String]) -> Int:
    return row.first

def middle(row: Row[Int, String]) -> List[String]:
    return row.middle

def last(row: Row[Int, String]) -> String:
    return row.last(1)

def nested(row: Row[Int, String]) -> Optional[String]:
    return row.nested.value

def method(row: Row[Int, String]) -> Int:
    return row.count()

def show(row: Row[Int, String]) -> String:
    return row.to_string()

type Plain:
    first: Int
    last: String

def plain(row: Plain) -> String:
    return row.last

type Empty:

export def main() -> Int:
    return 0
