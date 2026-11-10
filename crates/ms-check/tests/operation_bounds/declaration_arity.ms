fn read[T: Reader](value: T) Int: return 0

type Holder[T: Reader[Int, String]]:
    value: T

enum Choice[T: Reader]:
    Item(value: T)

interface Consumer[T: Reader[Int, String]]:
    fn consume(value: T) Int

interface Reader[A]:
    fn read() A
