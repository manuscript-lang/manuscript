type Source:
    number: Int

fn Source.choose[A, B = A](first: A, second: B) Int:
    return self.number

fn exercise() Int:
    source := Source(7)
    chosen := source.choose[Int]
    return chosen(1, 2)
