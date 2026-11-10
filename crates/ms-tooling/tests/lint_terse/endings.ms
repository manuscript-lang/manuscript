fn show(n: Int) Unit!:
    print("{n}")
    return ok(unit)

fn only() Unit!:
    return ok(unit)

fn quiet(n: Int) Unit:
    print("{n}")
    return

fn early(n: Int) Unit!:
    if n > 1:
        return ok(unit)
    print("{n}")

fn count() Int!:
    print("count")
    return ok(1)

fn main() Unit:
    _ := show(1)
    _ := only()
    quiet(2)
    _ := early(3)
    _ := count()
