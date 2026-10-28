from "@std/core.ms" import Closeable

type Res:
    name: String

impl Closeable for Res:
    var def close() -> Unit:
        return ()

# A value derived from the `with` resource cannot be stored where it outlives the block.
def main() -> Int:
    var kept = List[String]()
    var r = Res("b")
    let n = r.name
    kept.append(n)  # error: cannot move `n` out: it only borrows its value
    r.close()
    return kept.length()
