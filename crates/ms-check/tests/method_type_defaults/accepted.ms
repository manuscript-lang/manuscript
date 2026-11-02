interface Reader:
    fn read[T = Int]() Int

type Source:
    number: Int

impl Reader for Source:
    fn read[T = Int]() Int:
        return self.number

impl Source:
    fn choose[A, B = A](first: A, second: B) Int:
        return self.number

    fn fallback[T = Int](value: T?) Int:
        return self.number

    fn output[T = Int]() T?:
        return none

fn from_bound[S: Reader](source: S) Int:
    return source.read()

fn exercise() Int:
    let source = Source(7)
    let first = source.read()
    let explicit = source.read[String]()
    let partial = source.choose[Int](1, 2)
    let inferred = source.choose(1, "x")
    let fallback = source.fallback()
    let output: String? = source.output()
    return first + explicit + partial + inferred + fallback + output.get("").length() + from_bound(source)
