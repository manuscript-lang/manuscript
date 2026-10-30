import expect_true from "@std/test.ms"

fn scaled(base: Int, factor: Int = 2, label: String = "x") String: "{label}{base * factor}"

fn chained(base: Int, plus: Int = base + 1) Int: base + plus

fn maybe(value: Int, extra: Int?) Int:
    match extra:
        some(number):
            return value + number
        none:
            return value

fn countdown(n: Int, step: Int = 1) Int:
    if n <= 0:
        return 0

    return n + countdown(n: n - step, step: step)

test "omitted defaults":
    try expect_true((scaled(base: 3) == "x6"))
    try expect_true((scaled(base: 3, factor: 5) == "x15"))
    try expect_true((scaled(base: 3, factor: 5, label: "y") == "y15"))
    try expect_true((chained(base: 4) == 9 and chained(base: 4, plus: 1) == 5))
    try expect_true((maybe(value: 1) == 1 and maybe(value: 1, extra: some(4)) == 5))
    try expect_true((countdown(n: 4) == 10 and countdown(n: 4, step: 2) == 6))

    let callback = scaled
    try expect_true((callback(base: 2, factor: 3, label: "z") == "z6"))
