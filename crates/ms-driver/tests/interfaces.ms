import stdout from "@std/io.ms"
import {TextError} from "@std/errors.ms"

interface Shape:
    fn area() Int

type Sq:
    s: Int

impl Shape for Sq:
    fn area() Int:
        return self.s * self.s

fn total(x: Shape) Int:
    return x.area()

fn pick(n: Int) Result[Int, Error]:
    if n < 0:
        return error(TextError(text: "neg"))
    return ok(n)

fn twice(n: Int) Result[Int, Error]:
    let v = try pick(n)
    return ok(v * 2)

fn show(n: Int) Result[Unit, Error]:
    try stdout().write("{n}\n")
    return stdout().flush()

export fn main() Int:
    show(total(Shape(value: Sq(s: 4)))).get()
    show(twice(3).get()).get()
    let r = twice(0 - 1)
    if let v = r:
        show(v).get()
    else:
        show(99).get()
    return 0
