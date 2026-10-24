type Box:
    items: List[Int]

impl Box:
    fn list() ref List[Int]:
        return self.items

    fn pick(first: Bool) ref List[Int]:
        if first:
            return self.items

        return [1]

fn first_of[T](xs: List[T]) ref T:
    return xs[0]

fn forward(b: Box) ref List[Int]:
    return b.list()

fn read(b: Box) Int:
    let xs = b.list()
    let ys = b.pick(true)
    return xs.length() + ys.length()

fn temp(b: Box) Int:
    return b.list().length()

fn generic(rows: List[List[Int]]) Int:
    let row = first_of(rows)
    return row.length()

fn chain(b: Box) Int:
    let xs = forward(b)
    return xs.length()
