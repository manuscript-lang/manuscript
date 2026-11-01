import keep, measure from "@std/test/bench.ms"
import basename, join, normalize from "@std/os/fs.ms"
import parse, encode_component from "@std/net/net.ms"
import sqrt, sin from "@std/math/math.ms"

bench "path.join_normalize":
    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..50000:
            n += join(["/a", "b/../c", "d.txt"]) | normalize | .length()
        return keep(n)

    try measure(50000, work)

bench "path.basename":
    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..100000:
            n += basename("/a/b/c/file.txt").length()
        return keep(n)

    try measure(100000, work)

bench "url.parse":
    fn work() Result[Unit, Error]:
        let address = "https://example.com:8080/a/b?x=1&y=2#frag"
        var n = 0
        for i in 0..20000:
            if parse(address).is_ok(): n += 1
        return keep(n)

    try measure(20000, work)

bench "url.encode_component":
    fn work() Result[Unit, Error]:
        var n = 0
        for i in 0..50000:
            n += encode_component("a b&c=d/é").length()
        return keep(n)

    try measure(50000, work)

bench "math.sqrt_sin":
    fn work() Result[Unit, Error]:
        var acc = 0.0
        for i in 0..1000000:
            acc += sqrt(2.0) + sin(1.0)
        return keep(acc.truncate_to_int().get(0))

    try measure(1000000, work)
