// conform: tags=syntax,parser,formatter,ownership
// conform: phase=parse
// conform: origin=a result written `move T` hands over owned memory
type Box:
    n: Int

fn make() move Box:
    return Box(n: 1)

fn Box.dup() move Box:
    return Box(n: self.n)

fn apply(f: fn(Int) move Box) Int:
    return f(1).n

fn main() Void:
    g := fn(x: Int) move Box: Box(n: x)
    print(apply(g))
    print(make().n)
