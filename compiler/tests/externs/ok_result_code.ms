enum ReadError:
    Failed(code: Int, message: String)

extern fn read() String!ReadError
extern fn run() Void!ReadError

fn main() Void:
    return
