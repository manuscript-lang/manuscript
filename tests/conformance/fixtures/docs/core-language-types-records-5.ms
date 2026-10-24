# conform: tags=control-flow,diagnostics,interfaces,records,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/types/records.md:52
interface Counter:
    var def increment() -> Unit

type Val:
    val: Int

impl Counter for Val:
    var def increment() -> Unit:
        self.val = self.val + 1
