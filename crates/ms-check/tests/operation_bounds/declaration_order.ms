fn read[T: Reader[Int]](value: T) Int: return value.read()

type Holder[T: Reader[Int]]:
    value: T

enum Choice[T: Reader[Int]]:
    Item(value: T)

interface Consumer[T: Reader[Int]]:
    fn consume(value: T) Int

fn nested[T: Reader[Box[Int]]](value: T) Int: return value.read().value

type Box[A]:
    value: A

interface Reader[A]:
    fn read() A

fn compare[T: Compare[T]](value: T) Int: return value.compare(value)

interface Compare[A]:
    fn compare(other: A) Int
