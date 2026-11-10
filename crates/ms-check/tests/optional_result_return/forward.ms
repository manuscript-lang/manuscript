type Token:
    id: Int

fn f(r: Token?!) Token!?:
    if item := r.get():
        return ok(item)

    return none

fn main() Unit:
    return
