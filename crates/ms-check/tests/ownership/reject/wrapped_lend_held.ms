type Row:
    name: String
    tags: List[String]

type Bad:
    why: String

impl Reportable for Bad:
    fn message() String: self.why.clone()

fn risky(n: Int) Int!Bad:
    if n < 0: return error(Bad("negative"))

    return ok(n)

fn relay(result: Row!Bad, n: Int) Row!Bad:
    let _v = try risky(n)  # error: this function returns a reference into its arguments at 18:12 but a new value here; return `.clone()` of the part there, or build a new value on every path
    return result

fn demo(var r: Row) Int:
    let k: Row? = r
    r.name = "changed"  # error: cannot change `r.name` while `k` borrows it (binding of a borrowed value, at 21:9); finish using `k` before this, or give `k` its own value by ending its initializer with `.clone()`
    return k.get().name.length()

interface Reportable:
    fn message() String
