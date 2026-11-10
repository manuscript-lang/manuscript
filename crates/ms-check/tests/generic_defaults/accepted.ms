interface Reader[A]:
    fn read[T](value: T? = none, fallback: A? = none) Int
    fn implicit[U](value: U?) Int

type Source:
    number: Int

impl Reader[String] for Source:
    fn read[T](value: T?, fallback: String?) Int:
        return self.number

    fn implicit[U](value: U?) Int:
        return self.number

fn from_bound[S: Reader[String]](source: S) Int:
    return source.read[Int]()

fn exercise() Int:
    source := Source(7)
    omitted := source.read[Int]()
    inferred := source.read(3)
    implicit := source.implicit[String]()
    return omitted + inferred + implicit + from_bound(source)
