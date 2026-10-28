type Shelf:
    names: List[String]

fn make() Shelf:
    return Shelf(names: [])

fn either(a: Shelf, b: Shelf, flag: Bool) ref List[String]:
    if flag:
        return a.names

    return b.names

fn via(s: Shelf, flag: Bool) ref List[String]:  # error: no `return` gives back part
    return either(s, make(), flag)
