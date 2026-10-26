# A shape with two cases.
export type Shape:
    # A circle.
    case Circle(radius: Float)
    # A square.
    case Square(side: Float)
    case Empty

# Anything that can be measured.
export interface Measured:
    # The measured size.
    def size() -> Int

# A box of things.
export type Box[T]:
    # The contents.
    value: T
    count: Int = 1

impl Measured for Box[Int]:
    # Reports the count.
    def size() -> Int:
        return self.count

impl Equal for Shape:
    def equals(other: Shape) -> Bool:
        return True

export let LIMIT = 10
# The default name.
export let NAME: String = "x"
