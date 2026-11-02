type ReadError:
    case Failed(reason: String)

impl Error for ReadError:
    fn message() String:
        match self:
            Failed(reason): return reason.clone()

extern fn read_value() Int!ReadError

export fn main() Int:
    return 0
