# conform: tags=formatter,interfaces,modules,parser,stdlib-time,tier-io
# conform: phase=parse
# conform: origin=tests/e2e/inherent_methods_test.go:34 TestInherentImplRejections
import Duration from "@std/time.ms"
impl Duration:
    fn f() Int:
        return 1
