# conform: tags=closures,diagnostics,optional,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/optionals.md:86
def first_number(text: Optional[String]) -> Optional[Int]:
    return text.map(lambda value: value.trim().clone()).and_then(lambda value: value.parse_int())
