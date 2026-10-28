from "@std/core.ms" import Closeable

type Res:
    name: String

impl Closeable for Res:
    var def close() -> Unit:
        return ()

# fill, copy_within and merge store copies of what they are given.
def main() -> Int:
    var xs = [Res("a"), Res("b")]
    xs.fill(Res("c"), 0, 2)  # error: would copy the resources
    xs.copy_within(0, 1, 2)  # error: would copy the resources
    var a = Map[String, Res]()
    var b = Map[String, Res]()
    a.merge(b)  # error: would copy the resources
    return xs.length() + a.length()
