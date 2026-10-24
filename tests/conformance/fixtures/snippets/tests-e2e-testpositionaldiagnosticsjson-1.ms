# conform: tags=diagnostics,tier-core
# conform: phase=check
# conform: origin=tests/e2e/positional_arguments_test.go:46 TestPositionalDiagnosticsJSON
def f(first: Int, second: Int) -> Int: first

export def main() -> Int:
    return
