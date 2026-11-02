type ReadError:
    case Failed(message: String)

extern fn read_value() Int!ReadError

export fn main() Int:
    return 0
