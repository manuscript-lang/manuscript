type P[T]:
    v: T

interface Get[T]:
    fn get() T

fn P[T].get() T: self.v

fn f[T](g: Get[T]) T: g.get()

export fn main() Int:
    return f(P(1))
