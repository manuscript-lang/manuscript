// conform: tags=diagnostics,closures,maps,tier-core
// conform: phase=check
// conform: origin=ms-check/tests/messages.rs
fn transform(_0 Int, key String) Int => _0

fn wrong(values Map[String, Int]) Map[String, Int] => values.map(transform)
// expect-error: MS3001 6:66 expected fn(String, Int) Int, found fn(Int, String) Int (in argument 'transform' of values.map)
