# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=pkg/build/compiler_test.go:528 TestImplementationDeclarationParameters
interface Read[V]:
    fn get() V

type Pair[A, B: Clonable]:
    left: A
    right: B

impl Read[B] for Pair[Int, B]:
    fn get() B:
        return self.right.clone()
