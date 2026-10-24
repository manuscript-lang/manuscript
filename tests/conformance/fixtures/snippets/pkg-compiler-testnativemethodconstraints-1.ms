# conform: tags=diagnostics,interpolation,strings,tier-core
# conform: phase=check
# conform: origin=pkg/compiler/builtin_parity_test.go:9 TestNativeMethodConstraints
def stringify(value: Int) -> String:
    return f"{value}"

def wrong_label(item: Int) -> String:
    return f"{item}"

def callback() -> Unit:
    return ()
