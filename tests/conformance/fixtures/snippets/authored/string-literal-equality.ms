# conform: tags=strings,tier-io
# conform: phase=run
# conform: origin=string == short literal compiled inline
import stdout from "@std/io/io.ms"

fn score(s: String) Int:
    var n = 0
    if s == "a":
        n += 1
    if "héllo" == s:
        n += 2
    if s == "abcdefgh":
        n += 4
    if s == "abcde":
        n += 8
    if s == "":
        n += 16
    if s == "abcdefghi":
        n += 32
    return n

export fn main() Int:
    let all = ["a", "", "héllo", "abcdefgh", "abcde", "abcdef", "b", "é", "abcdefghi"]
    for s in all:
        let _i = stdout().write("{score(s)} ")
    return 0
