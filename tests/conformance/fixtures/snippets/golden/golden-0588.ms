// conform: tags=diagnostics
// conform: phase=check
fn transform(value Int, key String) Int => value

fn wrong(values Map[String, Int]) Map[String, Int] => values.map(transform)
// expect-error: MS3001 5:66 expected fn(String, Int) Int, found fn(Int, String) Int (in argument 'transform' of values.map)
