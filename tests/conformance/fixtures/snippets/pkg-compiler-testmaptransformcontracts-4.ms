# conform: tags=closures,diagnostics,maps,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/map_transforms_test.go:18 TestMapTransformContracts
def wrong(values: Map[String, Int]) -> Unit:
    let found = values.find_last(lambda k, v: v)
