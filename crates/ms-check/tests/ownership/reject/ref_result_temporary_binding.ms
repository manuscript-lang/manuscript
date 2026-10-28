type Shelf:
    names: List[String]

fn make() Shelf:
    return Shelf(names: ["made"])

fn either(a: Shelf, b: Shelf, flag: Bool) ref List[String]:
    if flag:
        return a.names

    return b.names

fn looped(s: Shelf) ref String:
    for name in either(s, make(), false):
        return name  # error: this one gives back an owned value
    return s.names[0]

fn bound(s: Shelf) ref List[String]:  # error: no `return` gives back part
    let names = either(s, make(), false)
    return names
