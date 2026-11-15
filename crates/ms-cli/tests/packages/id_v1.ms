export type Id:
    n: Int

export fn make() Id:
    return Id(n: 1)

export fn show(id: Id) String:
    return f"id {id.n}"
