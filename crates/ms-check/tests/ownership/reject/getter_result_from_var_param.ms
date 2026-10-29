type Box:
    items: List[Int]

impl Box:
    var fn list() List[Int]:
        return self.items  # error: cannot move
