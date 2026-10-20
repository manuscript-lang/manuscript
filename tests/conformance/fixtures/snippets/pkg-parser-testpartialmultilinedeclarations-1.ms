# conform: tags=parser,strings,tier-core
# conform: phase=parse
# conform: origin=pkg/parser/partial_test.go:72 TestPartialMultilineDeclarations
# prefix
fn first() Int:
    return 1
export fn echo(
value: String,
) String:
    return value
fn sum[
T,
](
left: Int,
right: Int,
) Int:
    return left + right
fn broken(
fn later() Int:
    return 2
