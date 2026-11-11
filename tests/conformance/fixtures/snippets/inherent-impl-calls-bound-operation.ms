// conform: tags=generics,interfaces,tier-io
// conform: phase=run
// conform: origin=thread/type-checker-bug-bash
import stdout from "@std/io/io.ms"

interface Scorer:
    fn score(x: Int) Int

type Dbl:
    k: Int

fn Dbl.score(x: Int) Int: x * self.k

type Wrap[T: Scorer]:
    inner: T

fn Wrap[T].run(x: Int) Int: self.inner.score(x)

fn via_param[T: Scorer](w: Wrap[T]) Int: w.inner.score(1)

fn main() Unit:
    stdout().write("{Wrap(Dbl(3)).run(2)} {via_param(Wrap(Dbl(1)))}\n").get()
