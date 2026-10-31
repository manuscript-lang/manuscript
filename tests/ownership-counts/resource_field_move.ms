# expect-stdout: both: moved second
# expect-stdout: close a1
# expect-stdout: main: a
# expect-stdout: branch: end
# expect-stdout: close b2
# expect-stdout: main: b
# expect-stdout: branch: end
# expect-stdout: close c2
# expect-stdout: close c1
# expect-stdout: main: c
# expect-stdout: close d2
# expect-stdout: early: kept
# expect-stdout: close e2
# expect-stdout: close e1
# expect-stdout: main: e
# expect-stdout: nested: moved
# expect-stdout: close fx
# expect-stdout: close f1
# expect-stdout: main: f
# expect-stdout: looped: end
# expect-stdout: close g2
# expect-stdout: local: end
# expect-stdout: close l1
# expect-stdout: close l2
# expect-stdout: main: end
# expect-stdout: close g1
# expect-stdout: close f2
# expect-stdout: close d1
# expect-stdout: close b1
# expect-stdout: close a2
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
    tag: String

type Wrap:
    room: Room
    extra: Door

fn say(s: String) Unit:
    stdout().write("{s}\n").get()

fn both(r: Room) List[Door]:
    var xs: List[Door] = []
    xs.append(r.second)
    say("both: moved second")
    return xs

fn branch(r: Room, flag: Bool) List[Door]:
    var xs: List[Door] = []
    if flag:
        xs.append(r.first)
    say("branch: end")
    return xs

fn early(r: Room, flag: Bool) List[Door]:
    var xs: List[Door] = []

    if flag:
        xs.append(r.first)
        return xs

    say("early: kept")
    return xs

fn nested(w: Wrap) List[Door]:
    var xs: List[Door] = []
    xs.append(w.room.second)
    say("nested: moved")
    return xs

fn looped(r: Room, n: Int) List[Door]:
    var xs: List[Door] = []

    for i in 0..n:
        if i == n - 1:
            xs.append(r.first)
            break

    say("looped: end")
    return xs

fn local() Unit:
    let r = Room(Door("l1"), Door("l2"), "t")
    var xs: List[Door] = []
    xs.append(r.first)
    say("local: end")

export fn main() Int:
    let _a = both(Room(Door("a1"), Door("a2"), "t"))
    say("main: a")

    let _b = branch(Room(Door("b1"), Door("b2"), "t"), true)
    say("main: b")

    let _c = branch(Room(Door("c1"), Door("c2"), "t"), false)
    say("main: c")

    let _d = early(Room(Door("d1"), Door("d2"), "t"), true)
    let _e = early(Room(Door("e1"), Door("e2"), "t"), false)
    say("main: e")

    let _f = nested(Wrap(Room(Door("f1"), Door("f2"), "t"), Door("fx")))
    say("main: f")

    let _g = looped(Room(Door("g1"), Door("g2"), "t"), 3)
    local()
    say("main: end")
    return 0
