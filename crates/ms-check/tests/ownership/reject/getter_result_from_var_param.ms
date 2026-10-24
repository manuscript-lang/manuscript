type Box:
    items: List[Int]

impl Box:
    var def list() -> List[Int]:
        return self.items  # error: cannot move
