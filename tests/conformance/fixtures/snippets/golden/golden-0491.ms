// conform: tags=diagnostics
// conform: phase=check
fn check(value Int, key String) Bool => true

fn wrong(value Map[String, Int]) Bool => value.every(check)
// expect-error: MS2001 5:48 unknown or ambiguous member every on Map[String, Int]; every(predicate) is now all(predicate)
