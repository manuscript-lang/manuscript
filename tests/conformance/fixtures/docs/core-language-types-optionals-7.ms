# conform: tags=closures,diagnostics,optional,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/optionals.md:86
fn first_number(text: Optional[String]) Optional[Int]:
    return text.map(fn(value): value.trim().clone()).and_then(fn(value): value.parse_int())
