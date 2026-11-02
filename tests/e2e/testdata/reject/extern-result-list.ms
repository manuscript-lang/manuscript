type ReadError:
    case Missing

extern fn read_values() List[Int]!ReadError

export fn main() Int:
    return 0
