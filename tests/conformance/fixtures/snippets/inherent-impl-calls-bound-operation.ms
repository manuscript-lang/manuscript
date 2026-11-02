# conform: tags=generics,interfaces,tier-io
# conform: phase=run
# conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io/io.ms"

interface Scorer:
    fn score(x: Int) Int

type Dbl:
    k: Int

impl Scorer for Dbl:
    fn score(x: Int) Int: x * self.k

type Wrap[T: Scorer]:
    inner: T

impl Wrap[T]:
    fn run(x: Int) Int: self.inner.score(x)

fn via_param[T: Scorer](w: Wrap[T]) Int: w.inner.score(1)

export fn main() Int:
    stdout().write("{Wrap(Dbl(3)).run(2)} {via_param(Wrap(Dbl(1)))}\n").get()
    return 0
