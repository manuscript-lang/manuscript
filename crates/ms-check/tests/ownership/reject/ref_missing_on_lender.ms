type Box:
    items: List[Int]

impl Box:
    fn list() List[Int]:  # error: write `ref` before its result type
        return self.items
