# conform: tags=maps,strings,tier-io
# conform: phase=run
# conform: origin=m.add(w.clone(), m.get(w).get(0) + 1) borrows w and copies the key only when it is absent
from "@std/io.ms" import stdout

def tally(words: List[String]) -> Map[String, Int]:
    var m = Map[String, Int]()

    for i in 0..words.length():
        let w = words.get(i)
        m.add(w.clone(), m.get(w).get(0) + 1)

    return m

export def main() -> Int:
    let m = tally(["a", "b", "a", "c", "a", "b"])
    let _ = stdout().write(
        f"{m.length()} {m.get("a").get(0)} {m.get("b").get(0)} {m.get("c").get(0)}\n"
    )
    return 0
