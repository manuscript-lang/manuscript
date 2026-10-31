# expect-stdout: close a1
# expect-stdout: close a2
# expect-stdout: main: a
# expect-stdout: after_move: ok
# expect-stdout: close b2
# expect-stdout: main: b
# expect-stdout: close c2
# expect-stdout: close c1
# expect-stdout: main: c
# expect-stdout: close d1
# expect-stdout: main: d
# expect-stdout: both_cond: end
# expect-stdout: close e2
# expect-stdout: both_cond: end
# expect-stdout: close f1
# expect-stdout: both_cond: end
# expect-stdout: both_cond: end
# expect-stdout: close h2
# expect-stdout: close h1
# expect-stdout: main: h
# expect-stdout: close i1
# expect-stdout: close j2
# expect-stdout: main: end
# expect-stdout: close j1
# expect-stdout: close i2
# expect-stdout: close g2
# expect-stdout: close g1
# expect-stdout: close f2
# expect-stdout: close e1
# expect-stdout: close d2
# expect-stdout: close b1
# A resource field moves out of an owned record: the new owner closes it once, and the record closes only the other fields, last declared first.
import stdout from "@std/io.ms"
import Closeable from "@std/core.ms"

type Door:
    name: String

impl Closeable for Door:
    var fn close() Unit!:
        stdout().write("close {self.name}\n").get()
        return ok(unit)

type Room:
    first: Door
    second: Door

type Oops:
    why: String

impl Error for Oops:
    fn message() String:
        return self.why.clone()

fn say(s: String) Unit:
    stdout().write("{s}\n").get()

fn check(fail: Bool) Int!Oops:
    if fail:
        return error(Oops("no"))

    return ok(1)

fn after_move(r: Room, fail: Bool) List[Door]!Oops:
    var xs: List[Door] = []
    xs.append(r.first)

    let _n = try check(fail)
    say("after_move: ok")
    return ok(xs)

fn before_move(r: Room, fail: Bool) List[Door]!Oops:
    let _n = try check(fail)
    var xs: List[Door] = []
    xs.append(r.second)
    return ok(xs)

fn both_cond(r: Room, a: Bool, b: Bool) List[Door]:
    var xs: List[Door] = []
    if a:
        xs.append(r.first)
    if b:
        xs.append(r.second)
    say("both_cond: end")
    return xs

fn whole_or_part(r: Room, flag: Bool) List[Door]:
    var xs: List[Door] = []

    if flag:
        xs.append(r.second)
    else:
        let moved = r
        xs.append(moved.first)

    return xs

export fn main() Int:
    let _a = after_move(Room(Door("a1"), Door("a2")), true)
    say("main: a")

    let _b = after_move(Room(Door("b1"), Door("b2")), false)
    say("main: b")

    let _c = before_move(Room(Door("c1"), Door("c2")), true)
    say("main: c")

    let _d = before_move(Room(Door("d1"), Door("d2")), false)
    say("main: d")

    let e = both_cond(Room(Door("e1"), Door("e2")), true, false)
    let f = both_cond(Room(Door("f1"), Door("f2")), false, true)
    let g = both_cond(Room(Door("g1"), Door("g2")), true, true)
    let h = both_cond(Room(Door("h1"), Door("h2")), false, false)
    say("main: h")

    let i = whole_or_part(Room(Door("i1"), Door("i2")), true)
    let j = whole_or_part(Room(Door("j1"), Door("j2")), false)
    say("main: end")
    if e.length() + f.length() + g.length() + h.length() + i.length() + j.length() != 6:
        return 1

    return 0
