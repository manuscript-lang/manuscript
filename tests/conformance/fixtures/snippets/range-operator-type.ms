# conform: tags=control-flow,diagnostics,tier-core
# conform: phase=check
# conform: origin=range operator a..b
export def main() -> Int:
    for i in 0.."x":
        return i
    return 0
