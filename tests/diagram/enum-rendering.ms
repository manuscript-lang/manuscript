type Item:
    value: Int

enum Choice[T]:
    missing
    found(value: T)
    paired(left: Item, right: List[T])

interface Reader:
    fn read() Int

type Box:
    choice: Choice[Int]
    reader: Reader
    case: Int

fn case(value: Int) Int:
    return value

fn inspect(box: Box) Int:
    return case(box.case)
