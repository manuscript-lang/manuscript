import Closeable from "@std/core.ms"

type Door:
    n: Int

impl Closeable for Door:
    var fn close() Unit:
        return

interface Sink:
    fn put(d: Door) Int

type Bin:
    count: Int

impl Sink for Bin:
    fn put(d: Door) Int:
        var xs = [d]
        return xs.length()

fn feed(s: Sink) Int:
    return s.put(Door(1))

fn f() Int:
    return feed(Bin(0))  # error: whose `put` keeps its `d`
