# conform: tags=diagnostics,generics,lists,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/generics.md:149
def repeat[T](value: T) -> Never:
    return repeat[T](value)  # Regular specialization; allowed.

def grow[T](value: T) -> Never:
    return grow[List[T]]([value])  # Rejected: expanding specialization.
