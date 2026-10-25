type Shelf:
    names: List[String]

def make() -> Shelf:
    return Shelf(names: ["made"])

def either(a: Shelf, flag: Bool, b: Shelf = make()) -> ref List[String]:
    if flag:
        return a.names
    return b.names

def via(s: Shelf) -> ref List[String]:  # error: no `return` gives back part
    return either(s, False)
