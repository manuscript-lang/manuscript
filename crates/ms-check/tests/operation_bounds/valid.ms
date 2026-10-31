interface Relation[T]:
    fn compare(other: T) Int

interface Reader[A]:
    fn read[T: Relation[T] & Relation[A]](value: T) Int

type Source:
    number: Int

impl Source:
    fn read[T: Relation[T]](value: T) Int:
        return self.number
