import Closeable from "@std/core.ms"

type Marker:
    id: Int

impl Closeable for Marker:
    var fn close() Unit!: ok(unit)

fn observe(value: Marker, changed: Int) Int: value.id + changed

fn change(var values: List[Marker]) Int:
    values.append(Marker(2))
    return 1

export fn main() Int:
    var values = [Marker(1)]
    return observe(values.first().get(), change(var values))  // error: overlaps argument
