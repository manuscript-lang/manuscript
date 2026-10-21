type Box:
    items: List[Int]

fn items_of(var b: Box) List[Int]:
    return b.items  # error: only a whole variable can move
