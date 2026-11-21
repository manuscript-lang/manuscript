enum ReadError:
    Missing
    Denied

extern fn read() Int!ReadError

fn main() Void:
    return
