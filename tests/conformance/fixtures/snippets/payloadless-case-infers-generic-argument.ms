// conform: tags=generics,alternatives,tier-io
// conform: phase=run
// conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io/io.ms"

enum Shape:
    Circle(r: Int)
    Dot

type Pair[A, B]:
    a: A
    b: B

fn id[T](x: T) T: x

fn name(s: Shape) String:
    match s:
        Circle(_): return "circle"
        Dot: return "dot"

export fn main() Int:
    p := Pair(Circle(1), Dot)
    q := Pair(Dot, 2)
    stdout().write("{name(id(Dot))} {name(p.a)} {name(p.b)} {name(q.a)} {q.b}\n").get()
    return 0
