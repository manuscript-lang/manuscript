from "@std/bench.ms" import keep, measure
from "@std/collections.ms" import range
from "@std/fs.ms" import basename, join, normalize
from "@std/net.ms" import parse, encode_component
from "@std/math.ms" import sqrt, sin

bench "path.join_normalize":
    def work() -> Result[Unit, Error]:
        var n = 0
        for i in range(0, 50000):
            n += join(["/a", "b/../c", "d.txt"]) | normalize | .length()
        return keep(n)

    try measure(50000, work)

bench "path.basename":
    def work() -> Result[Unit, Error]:
        var n = 0
        for i in range(0, 100000):
            n += basename("/a/b/c/file.txt").length()
        return keep(n)

    try measure(100000, work)

bench "url.parse":
    def work() -> Result[Unit, Error]:
        let address = "https://example.com:8080/a/b?x=1&y=2#frag"
        var n = 0
        for i in range(0, 20000):
            if parse(address).is_ok(): n += 1
        return keep(n)

    try measure(20000, work)

bench "url.encode_component":
    def work() -> Result[Unit, Error]:
        var n = 0
        for i in range(0, 50000):
            n += encode_component("a b&c=d/é").length()
        return keep(n)

    try measure(50000, work)

bench "math.sqrt_sin":
    def work() -> Result[Unit, Error]:
        var acc = 0.0
        for i in range(0, 1000000):
            acc += sqrt(2.0) + sin(1.0)
        return keep(acc.truncate_to_int().get(0))

    try measure(1000000, work)
