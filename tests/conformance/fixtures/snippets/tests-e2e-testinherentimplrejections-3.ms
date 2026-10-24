# conform: tags=diagnostics,interfaces,modules,stdlib-time,tier-io
# conform: phase=check
# conform: origin=tests/e2e/inherent_methods_test.go:34 TestInherentImplRejections
from "@std/time.ms" import Duration

impl Duration:
    def f() -> Int:
        return 1
