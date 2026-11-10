// conform: tags=formatter,generics,parser,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/contracts.md:146
fn invoke[T: Increment](operation: T) Int:
    return Increment(operation).apply(1)

from_concrete := invoke(offset)
from_view := invoke(view)
