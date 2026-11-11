// conform: tags=closures,formatter,generics,interpolation,parser,strings,testing,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/basics/text-and-bytes.md:52
fn text[T](value: T) String:
    return value.to_string()

test "string conversion":
    count := 3
    convert: fn() String := count.to_string
    _direct := count.to_string()
    _bound := convert()
    _embedded := "{count}"
