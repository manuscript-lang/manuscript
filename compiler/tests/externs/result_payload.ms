enum ReadError:
    Failed(reason: String)

extern fn read() Int!ReadError

fn main() Void:
    return
