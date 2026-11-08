import monotonic from "@std/time.ms"

fn primes(n: Int) Int:
    var composite = List[Bool](reserve: n + 1)
    for i in 0..n + 1:
        composite.append(false)
    var count = 0
    for i in 2..n + 1:
        if not composite[i]:
            count += 1
            var j = i * i
            while j < n + 1:
                composite[j] = true
                j += i
    return count

export fn main() Int:
    let start = monotonic()
    let count = primes(5000000)
    let ms = monotonic().difference(start).nanos / 1000000
    print("{count} primes below 5M in {ms} ms")
    return 0
