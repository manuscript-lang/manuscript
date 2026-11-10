import (
    Closeable, panic from "@std/core.ms",
    expect_equal from "@std/test/test.ms",
    promise from "@std/concurrency/promise.ms",
)

interface Src:
    var fn read(max: Int) Int?!Error
    var fn close() Unit

type Probe:
    action: Int

impl Src for Probe:
    var fn read(max: Int) Int?!Error:
        if self.action == 2: panic("source read failed")
        return ok(none)

    var fn close() Unit:
        return unit

type Wrapper:
    input: Src

impl Closeable for Wrapper:
    var fn close() Unit!:
        self.input.close()

impl Wrapper:
    var fn read() Int?!Error:
        return self.input.read(0)

fn run_wrapped(action: Int) Int!:
    _first := Wrapper(Probe(0))
    var last = Wrapper(Probe(action))
    result := last.read()
    return ok(if result.is_ok(): 0 else: 1)

test "consecutive promise faults in an interface read free each scope-closed wrapper once":
    var failed = 0

    for action in [2, 2, 2]:
        p := promise(fn: run_wrapped(action))
        if not p.wait().is_ok(): failed += 1

    try expect_equal(failed, 3)
