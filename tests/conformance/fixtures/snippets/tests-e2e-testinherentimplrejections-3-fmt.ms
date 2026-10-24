# conform: tags=formatter,interfaces,modules,parser,stdlib-time,tier-io
# conform: phase=parse
# conform: origin=tests/e2e/inherent_methods_test.go:34 TestInherentImplRejections
from "@std/time.ms" import Duration

impl Duration:
    def f() -> Int:
        return 1
