type ReadError:
    case Missing

impl Error for ReadError:
    fn message() String:
        return "missing"

extern fn read_values() List[Int]!ReadError

export fn main() Int:
    return 0
