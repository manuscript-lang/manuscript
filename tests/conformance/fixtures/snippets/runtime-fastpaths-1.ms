# conform: tags=strings,numbers,lists,interpolation,tier-stdlib
# conform: phase=run
# conform: origin=perf fast paths: builder append fusion, chars, parse_int, sort
import {stdout} from "@std/io.ms"
import {StringBuilder} from "@std/string.ms"
import {parse_int} from "@std/math.ms"

fn compare(left: Int, right: Int) Int:
    if left < right: return -1
    if left > right: return 1

    return 0

fn say(text: String) Unit:
    let _ignored = stdout().write(text)

export fn main() Int:
    var b = StringBuilder()
    var i = -3

    while i < 4:
        b.append("{i * 1000003},")
        b.append("<{i}>")
        i += 1

    b.append("{9223372036854775807}|{-9223372036854775807}|")

    let joined = b.freeze()
    say("{joined}\n")

    var total = 0

    for part in "12,-7,+5,x,,99999999999999999999,999999999999999999".split(","):
        if let v = part.parse_int():
            total += v
        else:
            total += 1

    say("{total}\n")

    var hits = 0
    for c in "hello wörld, ünï".chars():
        if c == "l":
            hits += 1
    say("{hits} {"naïve".chars().length()} {"".chars().length()}\n")

    var xs: List[Int] = []
    var k = 0

    while k < 200:
        xs.append(k * 7919 % 101)
        k += 1

    let sorted = xs.sorted(compare)
    say("{sorted.get(0)} {sorted.get(100)} {sorted.get(199)}\n")

    var ordered = true
    var j = 1

    while j < sorted.length():
        if sorted.get(j - 1) > sorted.get(j):
            ordered = false
        j += 1

    say("{ordered}\n")
    return 0
