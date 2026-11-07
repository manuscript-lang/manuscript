type P:
    id: Int

fn find() P?:
    return none

fn load() P!:
    return ok(P(id: 1))

fn main() Int:
    let a = find()
    let b = load()
    return a.id + b.id
