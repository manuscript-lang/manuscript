# conform: tags=generics,interfaces,tier-core
# conform: phase=run
# conform: origin=type-checker bug bash
interface Scorer[T]:
    fn score(x: T) Int

type Len:
    k: Int

impl Scorer[String] for Len:
    fn score(x: String) Int:
        return x.length() * self.k

impl Scorer[Int] for Len:
    fn score(x: Int) Int:
        return x * self.k

fn one[T, S: Scorer[T]](x: T, s: S) Int:
    return s.score(x)

export fn main() Int:
    return one("abc", Len(2)) + one(5, Len(3))
