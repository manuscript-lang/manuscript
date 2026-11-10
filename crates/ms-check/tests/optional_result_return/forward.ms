type Token:
    id: Int

fn f(r: Token?!) Token!?:
    if item := r.get():
        return ok(item)
    return none

export fn main() Int:
    return 0
