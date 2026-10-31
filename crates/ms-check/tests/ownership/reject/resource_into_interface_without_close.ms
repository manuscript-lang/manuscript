import Closeable from "@std/core.ms"

type Door:
    n: Int

impl Closeable for Door:
    var fn close() Unit!:
        return ok(unit)

interface Numbered:
    fn number() Int

impl Numbered for Door:
    fn number() Int:
        return self.n

fn read(x: Numbered) Int:
    return x.number()

fn f() Int:
    let d = Door(1)
    let v: Numbered = d  # error: is the resource `Door`
    return read(v)
