type Box:
    items: List[Int]

type Wrap:
    inner: Box

def f(b: Box, first: Bool) -> List[Int]:
    if first:
        return b.items  # error: also takes ownership

    let w = Wrap(inner: b)
    return []
