# conform: tags=diagnostics,closures,maps,tier-core
# conform: phase=check
# conform: origin=ms-check/tests/messages.rs
def transform(_0: Int, key: String) -> Int: _0
def wrong(values: Map[String, Int]) -> Map[String, Int]: values.map(transform)
