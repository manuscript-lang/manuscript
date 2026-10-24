type Box:
    items: List[Int]
    other: List[Int]

fn pick(b: Box, first: Bool) ref List[Int]:
    if first:
        return b.items
    return b.other

fn grow(var b: Box) Unit:
    var ys = pick(b, true)  # error: does not return one plain field path
    ys.append(1)
