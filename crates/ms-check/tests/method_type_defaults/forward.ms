interface Reader:
    fn read[T, U]() Int

type Source:
    number: Int

fn Source.read[T = U, U = Int]() Int:
    return self.number
