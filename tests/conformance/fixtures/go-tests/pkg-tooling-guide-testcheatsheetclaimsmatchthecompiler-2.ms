# conform: tags=interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/tooling/guide/guide_test.go:64 TestCheatsheetClaimsMatchTheCompiler
type T:
    a: Int

impl T:
    fn f(self) Int:
        return 1

export fn main() Int:
    return 0
