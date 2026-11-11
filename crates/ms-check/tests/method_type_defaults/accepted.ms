interface Reader:
    fn read[T = Int]() Int

type Source:
    number: Int

fn Source.read[T = Int]() Int:
    return self.number

fn Source.choose[A, B = A](first: A, second: B) Int:
    return self.number

fn Source.fallback[T = Int](value: T?) Int:
    return self.number

fn Source.output[T = Int]() T?:
    return none

fn from_bound[S: Reader](source: S) Int:
    return source.read()

fn exercise() Int:
    source := Source(7)
    first := source.read()
    explicit := source.read[String]()
    partial := source.choose[Int](1, 2)
    inferred := source.choose(1, "x")
    fallback := source.fallback()
    output: String? := source.output()
    return first + explicit + partial + inferred + fallback + output.get("").length() + from_bound(source)
