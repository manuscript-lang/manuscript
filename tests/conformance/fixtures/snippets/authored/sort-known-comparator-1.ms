# conform: tags=lists,tier-stdlib
# conform: phase=run
# conform: origin=perf: sorting with a named comparator is compiled with the program; results must match the runtime sort, including for inconsistent comparators
import stdout from "@std/io.ms"

fn up(left: Int, right: Int) Int:
    if left < right: return -1
    if left > right: return 1

    return 0

fn down(left: Int, right: Int) Int:
    return right - left

fn fup(left: Float, right: Float) Int:
    if left < right: return -1
    if left > right: return 1

    return 0

fn bad(left: Int, right: Int) Int:
    return 1

fn mod3(left: Int, right: Int) Int:
    return left % 3 - right % 3

fn main_run() Int:
    var seed = 12345
    var sum = 0
    var n = 0

    while n < 200:
        var v: List[Int] = []
        var f: List[Float] = []
        var i = 0

        while i < n:
            seed = (seed * 1103515245 + 12345) % 2147483648
            v.append(seed % 50)
            f.append((seed % 17).to_float())
            i += 1

        let a = v.sorted(up)
        let b = v.sorted(down)
        let c = f.sorted(fup)
        let d = v.sorted(bad)
        let e = v.sorted(mod3)
        var k = 0

        while k < n:
            sum = (
                (
                    sum * 31
                    + a.get(k) * 7
                    + b.get(k) * 3
                    + c.get(k).truncate_to_int().get(0)
                    + d.get(k) * 5
                    + e.get(k)
                )
                % 1000000007
            )
            k += 1

        n += 1

    return sum

export fn main() Int:
    let _w = stdout().write("{main_run()}\n")
    return 0
