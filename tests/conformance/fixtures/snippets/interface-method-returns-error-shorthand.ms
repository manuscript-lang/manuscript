# conform: tags=optional,try-result,tier-io
# conform: phase=run
# conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io.ms"
interface Parser[T]:
    fn parse(s: String) T!
type IntP:
    base: Int = 10
impl Parser[Int] for IntP:
    fn parse(s: String) Int!:
        return s.parse_int().ok_or()
fn run[T](p: Parser[T], s: String) T!:
    return p.parse(s)
fn all[T: Clonable](p: Parser[T], xs: List[String]) List[T]!:
    var out = List[T]()
    for x in xs:
        out.append(try p.parse(x))
    return ok(out)
type Cb:
    f: fn(Int) Int!
fn apply(c: Cb, x: Int) Int!:
    return c.f(x)
export fn main() Int:
    let p = IntP()
    let r = run[Int](p, "42")
    stdout().write("{r.get(0)}\n").get()
    let l = all[Int](p, ["1", "2", "x"])
    stdout().write("{l.is_ok()}\n").get()
    let l2 = all[Int](p, ["1", "2"])
    stdout().write("{l2.get([]).length()}\n").get()
    let c = Cb(fn x: ok(x + 1))
    stdout().write("{apply(c, 1).get(0)}\n").get()
    return 0
