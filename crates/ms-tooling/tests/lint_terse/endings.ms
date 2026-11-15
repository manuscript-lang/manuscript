fn show(n: Int) Void!:
    print("{n}")
    return ok(unit)

fn only() Void!:
    return ok(unit)

fn quiet(n: Int) Void:
    print("{n}")
    return

fn early(n: Int) Void!:
    if n > 1:
        return ok(unit)
    print("{n}")

fn count() Int!:
    print("count")
    return ok(1)

fn main() Void:
    _ := show(1)
    _ := only()
    quiet(2)
    _ := early(3)
    _ := count()
