type Source:
    number: Int

impl Source:
    fn choose[A, B = A](first: A, second: B) Int:
        return self.number

fn exercise() Int:
    let source = Source(7)
    let chosen = source.choose[Int]
    return chosen(1, 2)
