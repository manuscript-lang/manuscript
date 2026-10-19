# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=pkg/build/compiler_test.go:528 TestImplementationDeclarationParameters
interface Read[V]:
    fn get() V
type Pair[A, B]:
    left: A
    right: B
impl Read[B] for Pair[Int, B]:
    fn get() B:
        return self.right
