# conform: tags=diagnostics,closures,functions,tier-core
# conform: phase=check
# conform: origin=ms-build/tests/callable_defaults.rs
def original(value: Int = 7) -> Int: value + 1
def replacement(value: Int) -> Int: value + 2
export def main() -> Int:
    var callback = original
    callback = replacement
    return callback()
