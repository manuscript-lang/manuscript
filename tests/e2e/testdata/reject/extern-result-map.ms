enum ReadError:
    case Missing

extern fn read_values() Map[String, Int]!ReadError

export fn main() Int:
    return 0
