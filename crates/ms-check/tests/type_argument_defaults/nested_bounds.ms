fn read[T = Map[List[Int], Int]](value: T) T: return value

type Holder[T = Map[List[Int], Int]]:
    value: T

interface Reader[A]:
    fn read[B = Map[A, Int]](value: B) Int

impl Holder[T]:
    fn read[U = Map[List[Int], Int]](value: U) Int: return 0
