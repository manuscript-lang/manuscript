# conform: tags=closures,formatter,lists,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/functions/function-values-and-closures.md:99
def names() -> List[String]:
    return [1, 2].map(lambda value: value.to_string())
