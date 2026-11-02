interface Reader:
    fn read[T, U]() Int

type Source:
    number: Int

impl Reader for Source:
    fn read[T = U, U = Int]() Int:
        return self.number
