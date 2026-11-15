fn show(n: Int) Void!:
    print("{n}")
    return ok(void)

fn only() Void!:
    return ok(void)

fn quiet(n: Int) Void:
    print("{n}")
    return

fn early(n: Int) Void!:
    if n > 1:
        return ok(void)
    print("{n}")

fn count() Int!:
    print("count")
    return ok(1)

fn main() Void:
    void show(1)
    void only()
    quiet(2)
    void early(3)
    void count()
