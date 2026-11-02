type Row:
    name: String

fn label(r: Row) String:
    return r.name

fn pick(a: Row, flag: Bool) String:
    return if flag: a.name else: "lit"  # error: this function returns a reference into its arguments at 8:23 but a new value here; return `.clone()` of the part there, or build a new value on every path

fn demo(var a: Row, var b: Row) Int:
    let w = if a.name == "a": label(a) else: label(b)
    a.name = "changed"  # error: cannot change `a.name` while `w` borrows it (binding of a part of it, at 11:9); finish using `w` before this, or give `w` its own value by ending its initializer with `.clone()`
    return w.length()
