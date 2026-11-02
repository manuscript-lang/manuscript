interface Reader:
    fn read[T](value: T) Int

type Source:
    number: Int

impl Reader for Source:
    fn read[T: Int](value: T) Int:
        return self.number
