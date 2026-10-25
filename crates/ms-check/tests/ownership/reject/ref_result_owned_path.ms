type Shelf:
    names: List[String]

def pick(s: Shelf, flag: Bool) -> ref List[String]:
    if flag:
        return s.names
    return ["fresh"]  # error: so every path must return part of a parameter
