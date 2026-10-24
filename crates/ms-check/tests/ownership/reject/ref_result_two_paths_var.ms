type Box:
    items: List[Int]
    other: List[Int]

def pick(b: Box, first: Bool) -> ref List[Int]:
    if first:
        return b.items

    return b.other

def grow(var b: Box) -> Unit:
    var ys = pick(b, True)  # error: does not return one plain field path
    ys.append(1)
