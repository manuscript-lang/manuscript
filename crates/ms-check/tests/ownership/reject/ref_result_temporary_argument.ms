type Shelf:
    names: List[String]

def make() -> Shelf:
    return Shelf(names: [])

def either(a: Shelf, b: Shelf, flag: Bool) -> ref List[String]:
    if flag:
        return a.names
    return b.names

def via(s: Shelf, flag: Bool) -> ref List[String]:  # error: no `return` gives back part
    return either(s, make(), flag)
