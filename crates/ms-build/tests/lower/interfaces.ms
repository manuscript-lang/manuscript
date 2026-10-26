# Lowered and verified by tests/lower.rs; each expect line is checked against the printed MIR.
# expect-mir: "iface.new"
# expect-mir: "call.method"

from "@std/io.ms" import stdout
from "@std/core.ms" import TextError

interface Shape:
    def area() -> Int

type Sq:
    s: Int

impl Shape for Sq:
    def area() -> Int:
        return self.s * self.s

def total(x: Shape) -> Int:
    return x.area()

def pick(n: Int) -> Result[Int, Error]:
    if n < 0:
        return error(TextError(text: "neg"))

    return ok(n)

def twice(n: Int) -> Result[Int, Error]:
    let v = try pick(n)
    return ok(v * 2)

def show(n: Int) -> Result[Unit, Error]:
    try stdout().write(f"{n}\n")
    return stdout().flush()

export def main() -> Int:
    show(total(Sq(s: 4))).get()
    show(twice(3).get()).get()

    let r = twice(0 - 1)

    if let v = r:
        show(v).get()
    else:
        show(99).get()

    return 0
