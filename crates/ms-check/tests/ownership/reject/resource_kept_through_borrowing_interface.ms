import Closeable from "@std/core.ms"

type Door:
    n: Int

fn var Door.close() Unit!:
    return ok(unit)

interface Sink:
    fn put(d: Door) Int

type Bin:
    count: Int

fn Bin.put(d: Door) Int:
    var xs = [d]
    return xs.length()

fn feed(s: Sink) Int:
    return s.put(Door(1))

fn f() Int:
    return feed(Bin(0))  // error: whose `put` keeps its `d`
