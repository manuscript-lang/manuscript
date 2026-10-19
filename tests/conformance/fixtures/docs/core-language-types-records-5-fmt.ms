# conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
# conform: phase=parse
# conform: origin=documentation/core-language/types/records.md:52
interface Counter:
    fn increment() Unit

type Val:
    val: Int

impl Counter for Val:
    fn increment() Unit:
        self.val = self.val + 1
