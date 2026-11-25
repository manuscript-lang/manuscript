// conform: tags=diagnostics,maps,strings,tier-core
// conform: phase=check
// conform: origin=pkg/compiler/map_transforms_test.go:16 TestMapTransformContracts
fn transform(value Int, key String) Int => value

fn wrong(values Map[String, Int]) Map[String, Int] => values.map(transform)
// expect-error: MS3001 6:66 expected fn(String, Int) Int, found fn(Int, String) Int (in argument 'transform' of values.map)
