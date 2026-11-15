fn show(n: Int) Void!:
    print(f"{n}")
    return ok()

fn only() Void!:
    return ok()

fn quiet(n: Int) Void:
    print(f"{n}")
    return

fn early(n: Int) Void!:
    if n > 1:
        return ok()
    print(f"{n}")

fn count() Int!:
    print("count")
    return ok(1)

fn main() Void:
    void show(1)
    void only()
    quiet(2)
    void early(3)
    void count()
