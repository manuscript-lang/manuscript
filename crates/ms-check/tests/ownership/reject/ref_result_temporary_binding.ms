type Shelf:
    names: List[String]

def make() -> Shelf:
    return Shelf(names: ["made"])

def either(a: Shelf, b: Shelf, flag: Bool) -> ref List[String]:
    if flag:
        return a.names
    return b.names

def looped(s: Shelf) -> ref String:
    for name in either(s, make(), False):
        return name  # error: this one gives back an owned value
    return s.names[0]

def bound(s: Shelf) -> ref List[String]:  # error: no `return` gives back part
    let names = either(s, make(), False)
    return names
