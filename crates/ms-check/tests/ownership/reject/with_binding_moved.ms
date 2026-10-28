import Closeable from "@std/core.ms"

type Res:
    name: String

impl Closeable for Res:
    fn close() Unit:
        return unit

fn keep(r: Res) Res:
    return r

fn main() Unit:
    with let r = Res("a"):
        let moved = keep(r)  # error: its `with` block closes it at the end of the block
        let _ = moved.name
