// conform: tags=control-flow,formatter,interfaces,parser,records,tier-core
// conform: phase=parse
// conform: origin=documentation/core-language/types/named-types.md:52
interface Counter:
    var fn increment() Unit

type Val:
    val: Int

fn var Val.increment() Unit:
    self.val = self.val + 1
