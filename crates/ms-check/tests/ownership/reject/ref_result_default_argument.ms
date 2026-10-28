type Shelf:
    names: List[String]

fn make() Shelf:
    return Shelf(names: ["made"])

fn either(a: Shelf, flag: Bool, b: Shelf = make()) ref List[String]:
    if flag:
        return a.names

    return b.names

fn via(s: Shelf) ref List[String]:  # error: no `return` gives back part
    return either(s, false)
