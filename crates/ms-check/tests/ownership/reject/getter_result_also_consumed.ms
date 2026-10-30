type Box:
    items: List[Int]

type Wrap:
    inner: Box

fn f(b: Box, first: Bool) ref List[Int]:  # error: returns `ref`
    if first:
        return b.items  # error: also takes ownership

    let w = Wrap(inner: b)
    return []
