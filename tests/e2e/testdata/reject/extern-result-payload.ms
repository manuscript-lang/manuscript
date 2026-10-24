type ReadError:
    case Failed(message: String)

impl Error for ReadError:
    def message() -> String:
        match self:
            case Failed(message): return message

extern def read_value() -> Result[Int, ReadError]

export def main() -> Int:
    return 0
