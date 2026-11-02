type ReadError:
    case Failed(reason: String)

extern fn read_value() Int!ReadError

export fn main() Int:
    return 0
