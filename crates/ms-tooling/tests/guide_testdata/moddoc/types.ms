// A shape with two cases.
export enum Shape:
    // A circle.
    Circle(radius: Float)
    // A square.
    Square(side: Float)
    Empty

// Anything that can be measured.
export interface Measured:
    // The measured size.
    fn size() Int

// A box of things.
export type Box[T]:
    // The contents.
    value: T
    count: Int = 1

// Reports the count.
fn Box[Int].size() Int:
    return self.count

fn Shape.equals(other: Shape) Bool:
    return true

export LIMIT := 10
// The default name.
export NAME: String := "x"
