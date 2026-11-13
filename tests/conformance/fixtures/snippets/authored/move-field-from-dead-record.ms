// conform: tags=records,lists,scope-cleanup
// conform: phase=run
// conform: origin=copyelim type.release
import stdout from "@std/io/io.ms"

type Pair:
    left: List[String]
    right: List[String]
    tag: String

fn left_of(p: Pair) List[String]: p.left.clone()

fn tag_of(p: Pair) String: p.tag.clone()

fn make(n: Int) Pair:
    var l = List[String]()
    var r = List[String]()

    for i in 0..n:
        l.append("l{i}")
        r.append("r{i}")

    return Pair(l, r, "t{n}")

fn main() Unit:
    l := left_of(make(3))
    t := tag_of(make(2))
    stdout().write("{l.join(",")} {t}\n").get()
