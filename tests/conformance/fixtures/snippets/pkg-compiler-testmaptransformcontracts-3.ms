# conform: tags=diagnostics,maps,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/map_transforms_test.go:16 TestMapTransformContracts
def transform(value: Int, key: String) -> Int: value

def wrong(values: Map[String, Int]) -> Map[String, Int]: values.map(transform)
