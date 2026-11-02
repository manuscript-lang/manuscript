# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=range operator a..b
export fn main() Int:
    for i in 0..2..4:
        return i
    return 0
