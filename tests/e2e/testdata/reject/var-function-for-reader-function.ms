type P:
    n: Int

fn run(f: fn(P) Unit) Unit:
    let _ = f

fn changes(var p: P) Unit:
    p.n = 1

test "a function that changes its parameter is not one that only reads it":
    run(changes)
