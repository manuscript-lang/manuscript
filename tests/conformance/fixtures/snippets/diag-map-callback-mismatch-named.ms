# conform: tags=diagnostics,closures,maps,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def transform(value: Int, key: String) -> Int: value
def wrong(values: Map[String, Int]) -> Map[String, Int]: values.map(transform)
