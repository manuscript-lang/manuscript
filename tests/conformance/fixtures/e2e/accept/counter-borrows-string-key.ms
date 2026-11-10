// conform: tags=maps,strings,tier-io
// conform: phase=run
// conform: origin=m.add(w.clone(), m.get_or(w, 0) + 1) borrows w and copies the key only when it is absent
import stdout from "@std/io/io.ms"

fn tally(words: List[String]) Map[String, Int]:
    var m = Map[String, Int]()

    for i in 0..words.length():
        let w = words.get(i)
        m.add(w.clone(), m.get_or(w, 0) + 1)

    return m

fn main() Unit:
    let m = tally(["a", "b", "a", "c", "a", "b"])
    let _ = stdout().write(
        "{m.length()} {m.get_or("a", 0)} {m.get_or("b", 0)} {m.get_or("c", 0)}\n"
    )
