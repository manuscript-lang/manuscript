import Closeable from "@std/core.ms"

type Plain:
    a: Int

type HasList:
    xs: List[String]

type HasFn:
    f: fn(Int) Int

enum Choice:
    A
    B(x: Int)

enum Payload:
    P(s: String)
    Q(p: Plain)

type Res:
    n: Int

fn var Res.close() Unit!:
    return ok(unit)

type HoldsRes:
    r: Res

type ListOfRes:
    rs: List[Res]

type OptRes:
    r: Res?

type Box[T]:
    v: T

enum Recur:
    Leaf
    Node(next: List[Recur])

fn need[T: Clonable](x: T) Unit:
    print("")
