interface Reader:
    fn read[T: Hashable]() Int

type Source:
    number: Int

impl Reader for Source:
    fn read[T: Hashable = fn() Int]() Int:
        return self.number
