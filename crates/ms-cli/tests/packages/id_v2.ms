export type Id:
    n: Int
    tag: String

export fn make() Id:
    return Id(n: 1, tag: "t")

export fn show(id: Id) String:
    return f"id {id.n}"
