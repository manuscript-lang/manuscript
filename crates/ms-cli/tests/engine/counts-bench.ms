import keep from "@std/test/bench.ms"

bench "builds a list":
    var xs: List[Int] = []
    for i in 0..SIZE:
        xs.append(i)
    keep(xs.length())?
