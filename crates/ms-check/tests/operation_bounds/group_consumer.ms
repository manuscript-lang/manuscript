import Reader from "./provider.ms"

export fn read[T: Reader[Int]](value: T) Int: return value.read()
