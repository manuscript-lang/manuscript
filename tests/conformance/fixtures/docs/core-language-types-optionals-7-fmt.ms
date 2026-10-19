# conform: tags=closures,formatter,optional,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/optionals.md:86
fn first_number(text: Optional[String]) Optional[Int]:
    return text.map(fn(value): value.trim()).and_then(fn(value): value.parse_int())
