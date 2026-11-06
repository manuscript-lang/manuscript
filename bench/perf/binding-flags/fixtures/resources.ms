import stdout from "@std/io/io.ms"
import Closeable from "@std/core.ms"

type Res:
    id: Int
    open: Bool = true

impl Closeable for Res:
    var fn close() Unit!:
        if self.open:
            self.open = false
            stdout().write("close {self.id}\n").get()

        return ok(unit)

fn borrowed(values: List[Int]) Int:
    let a = values
    let b = a
    return a.length() + b.length() + values.length()

type Holder:
    items: List[Int]

fn mutate(var holder: Holder) Unit:
    var alias = holder.items
    alias.append(9)

fn conditional(flag: Bool) Unit:
    var value = Res(1)
    if flag:
        value.close().get()

    let _after = Res(2)

fn move_through(value: Res) Res:
    return value

fn conditional_move(flag: Bool) Unit:
    let value = Res(3)
    if flag:
        let _moved = move_through(value)

    let _last = Res(4)

export fn main() Int:
    var values = [1, 2]
    let count = borrowed(values)
    var holder = Holder(values)
    mutate(var holder)
    stdout().write("{count} {holder.items.length()}\n").get()
    conditional(true)
    conditional(false)
    conditional_move(true)
    conditional_move(false)
    return 0
