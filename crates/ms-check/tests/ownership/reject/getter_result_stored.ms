type Box:
    items: List[Int]

impl Box:
    fn list() ref List[Int]:
        return self.items

fn f(b: Box) List[List[Int]]:
    var saved: List[List[Int]] = []
    saved.append(b.list())  # error: borrows its result from `b`
    return saved
