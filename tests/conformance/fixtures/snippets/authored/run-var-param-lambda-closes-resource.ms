// conform: tags=closures,tier-core
// conform: phase=run
// A lambda with a `var` parameter whose body closes a resource builds and runs.
import pipe, Pipe, ReadStream from "@std/io/io.ms"

type Handlers:
    items: List[fn(var Int, Int) Void!]

fn var Handlers.add(move f: fn(var Int, Int) Void!) Void:
    self.items.append(f)

fn make(p: Pipe[Int]) Handlers:
    var h = Handlers(items: List[fn(var Int, Int) Void!]())
    h.add(fn var total, n:
        var out = p.writer()
        out.write(n)?
        out.close()?
        total += n
        return ok()
    )
    return h

export fn main() Int:
    var p = pipe[Int](capacity: 4)
    h := make(p)
    var total = 0
    for f in h.items:
        f(total, 5).get_or_else(fn e: void)
    print(f"{total}")
    return 0
