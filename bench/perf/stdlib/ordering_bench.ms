from "@std/bench.ms" import keep, measure

# `a.min(b)` and `a.clamp(low, high)` against the same comparison written with `if`; both should cost the same.
bench "ordering.min_method":
    def work() -> Result[Unit, Error]:
        var total = 0
        for i in 0..1000000:
            total += ((i * 7919) % 10007).min(5000)
        return keep(total)

    try measure(1000000, work)

bench "ordering.min_if":
    def work() -> Result[Unit, Error]:
        var total = 0

        for i in 0..1000000:
            let value = (i * 7919) % 10007

            if value < 5000:
                total += value
            else:
                total += 5000

        return keep(total)

    try measure(1000000, work)

bench "ordering.clamp_method":
    def work() -> Result[Unit, Error]:
        var total = 0
        for i in 0..1000000:
            total += ((i * 7919) % 10007).clamp(2000, 8000)
        return keep(total)

    try measure(1000000, work)

bench "ordering.clamp_if":
    def work() -> Result[Unit, Error]:
        var total = 0

        for i in 0..1000000:
            let value = (i * 7919) % 10007

            if value < 2000:
                total += 2000
            elif value > 8000:
                total += 8000
            else:
                total += value

        return keep(total)

    try measure(1000000, work)
