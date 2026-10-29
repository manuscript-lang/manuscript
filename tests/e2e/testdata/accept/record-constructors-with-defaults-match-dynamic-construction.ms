import expect_true from "@std/test.ms"

fn twice(n: Int) Int: n * 2

type Options:
    count: Int
    total: Int = count + 1
    label: String = "x"
    scale: Float = 1.5
    scaled: Int = twice(n: total)

type Plain:
    name: String = "p"
    size: Int = 3

test "constructors":
    let a = Options(count: 5)
    try expect_true(
        (a.total == 6 and a.label == "x" and a.scale == 1.5 and a.scaled == 12)
    )

    let b = Options(count: 5, total: 0)
    try expect_true((b.total == 0 and b.scaled == 0))

    let c = Options(count: 1, total: 2, label: "y", scale: 2.0, scaled: 9)
    try expect_true((c.label == "y" and c.scaled == 9 and c.scale == 2.0))

    let d = Options(label: "z", count: 4)
    try expect_true((d.label == "z" and d.total == 5))

    let e = Plain()
    try expect_true((e.name == "p" and e.size == 3))
    try expect_true((Plain(size: 9).size == 9 and Plain(size: 9).name == "p"))
