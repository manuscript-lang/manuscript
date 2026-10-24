# conform: tags=formatter,generics,lists,parser,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/generics.md:149
def repeat[T](value: T) -> Never:
    return repeat[T](value)  # Regular specialization; allowed.

def grow[T](value: T) -> Never:
    return grow[List[T]]([value])  # Rejected: expanding specialization.
