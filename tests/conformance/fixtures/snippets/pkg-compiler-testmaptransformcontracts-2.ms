# conform: tags=closures,diagnostics,maps,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/map_transforms_test.go:14 TestMapTransformContracts
def wrong[W](values: Map[String, Int], transform: Callable[[String, Int], W]) -> Unit:
    let mapped = values.map_keys(transform)
