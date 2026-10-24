type ReadError:
    case Missing

impl Error for ReadError:
    def message() -> String:
        return "missing"

extern def read_values() -> Result[List[Int], ReadError]

export def main() -> Int:
    return 0
