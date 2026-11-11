type Source:
    number: Int

fn Source.read[T: Int](value: T) Int:
    return self.number
