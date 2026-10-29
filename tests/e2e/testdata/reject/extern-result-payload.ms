type ReadError:
    case Failed(message: String)

impl Error for ReadError:
    fn message() String:
        match self:
            Failed(message): return message

extern fn read_value() Result[Int, ReadError]

export fn main() Int:
    return 0
