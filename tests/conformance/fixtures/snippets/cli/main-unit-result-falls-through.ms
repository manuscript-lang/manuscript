// conform: tags=functions,tier-core
// conform: phase=run
fn step(n: Int) Unit!:
    if n > 2:
        return error(Error("too big"))
    print("step {n}")

fn main() Unit!:
    try step(1)
    try step(2)
    try step(3)
    print("unreachable")
