from "@std/core.ms" import Closeable

type Res:
    name: String

impl Closeable for Res:
    var def close() -> Unit:
        return ()

# A value derived from a resource cannot be used once the resource is closed.
def main() -> Unit:
    var r = Res("a")
    let n = r.name
    r.close()  # error: cannot change `r` while `n` borrows it

    let _ = n.length()
