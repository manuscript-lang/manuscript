type Box:
    items: List[Int]

fn items_of(b: Box) List[Int]:
    return b.items  # error: only a whole variable can move
