# conform: tags=closures,formatter,mutation,parser,strings,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/functions/function-values-and-closures.md:52
def make_headline() -> Callable[[], String]:
    var subject = "Weekly update"
    let headline = lambda:
        return subject
    subject = "Launch announcement"
    return headline
# make_headline()() returns "Weekly update".
