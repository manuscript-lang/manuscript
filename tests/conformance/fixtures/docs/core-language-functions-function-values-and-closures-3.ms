# conform: tags=closures,diagnostics,mutation,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/functions/function-values-and-closures.md:52
fn make_headline() fn() String:
    var subject = "Weekly update"
    let headline = fn():
        return subject.clone()
    subject = "Launch announcement"
    return headline
# make_headline()() returns "Weekly update".
