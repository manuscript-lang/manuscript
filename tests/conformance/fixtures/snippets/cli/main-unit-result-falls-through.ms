// conform: tags=functions,tier-core
// conform: phase=run
fn step(n: Int) Unit!:
    if n > 2:
        return error(Error("too big"))
    print("step {n}")

fn main() Unit!:
    step(1)?
    step(2)?
    step(3)?
    print("unreachable")
