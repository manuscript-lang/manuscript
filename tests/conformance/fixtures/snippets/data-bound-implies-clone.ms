# conform: tags=generics,tier-io
# conform: phase=check
# conform: origin=thread/type-checker-bug-bash
import Data from "@std/core.ms"

fn a[T: Hashable](x: T) T: x.clone()

fn b[T: Data](x: T) T: x.clone()

fn c[T: Hashable](xs: List[T]) List[T]: xs.take(1)

fn d[T: Data](xs: List[T]) List[T]: xs.concat(xs)

fn e[T: Hashable](m: Map[T, Int]) Map[T, Int]: m.clone()

export fn main() Int:
    return a(1) + b(2)
