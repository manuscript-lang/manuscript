# conform: tags=closures,formatter,maps,parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/compiler/map_transforms_test.go:14 TestMapTransformContracts
def wrong[W](values: Map[String, Int], transform: Callable[[String, Int], W]) -> Unit:
    let mapped = values.map_keys(transform)
