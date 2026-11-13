import stdout from "@std/io/io.ms"

fn dup(s: String, n: Int) String:
    var i = 0
    while i < n:
        i += 1
    return s.clone()

fn spin(xs: List[Int], n: Int) List[Int]:
    var i = 0
    while i < n:
        i += 1
    return xs.clone()

fn drop_after(s: String, n: Int) Int:
    t := s.clone()
    if t.length() == 99999:
        return 0
    var i = 0
    while i < n:
        i += 1
    return i

fn say(text: String) Unit:
    _ := stdout().write("{text}\n")

export fn main() Int:
    say(dup("a long string that is certainly not inline", 3))
    say(dup("hi", 2))
    say("{spin([1, 2, 3], 4).length()} {drop_after("a long string that is certainly not inline", 5)} {drop_after("tiny", 6)}")
    return 0
