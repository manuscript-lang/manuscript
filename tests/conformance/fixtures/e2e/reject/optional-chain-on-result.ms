// conform: tags=testing,tier-core
// conform: phase=check
fn load() Int!:
    return ok(1)

fn main() Void:
    n := load()?.abs()
    print(n)
