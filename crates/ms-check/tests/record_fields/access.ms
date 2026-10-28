type Box[T]:
    value: T

type Row[A, B]:
    first: A
    middle: List[B]
    last: fn(A) B
    nested: Box[Optional[B]]
    to_string: Int

impl Row[A, B]:
    fn count() Int:
        return 1

fn first(row: Row[Int, String]) Int:
    return row.first

fn middle(row: Row[Int, String]) List[String]:
    return row.middle

fn last(row: Row[Int, String]) String:
    return row.last(1)

fn nested(row: Row[Int, String]) Optional[String]:
    return row.nested.value

fn method(row: Row[Int, String]) Int:
    return row.count()

fn show(row: Row[Int, String]) String:
    return row.to_string()

type Plain:
    first: Int
    last: String

fn plain(row: Plain) String:
    return row.last

type Empty:

export fn main() Int:
    return 0
