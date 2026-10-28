from "@std/core.ms" import Closeable

type Res:
    name: String

impl Closeable for Res:
    def close() -> Unit:
        return ()

def keep(r: Res) -> Res:
    return r

def main() -> Unit:
    with let r = Res("a"):
        let moved = keep(r)  # error: its `with` block closes it at the end of the block
        let _ = moved.name
