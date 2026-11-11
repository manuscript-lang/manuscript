type Source:
    number: Int

fn Source.read[T: Hashable = fn() Int]() Int:
    return self.number
