import Closeable from "@std/core.ms"

type Door:
    n: Int

fn var Door.close() Unit!:
    return ok(unit)

interface Numbered:
    fn number() Int

fn Door.number() Int:
    return self.n

fn read(x: Numbered) Int:
    return x.number()

fn f() Int:
    d := Door(1)
    v: Numbered := d  // error: is the resource `Door`
    return read(v)
