# conform: tags=diagnostics,lists,strings,tier-core
# conform: phase=check
# conform: origin=documentation/core-language/modules/declarations.md:32
export let MAX_ITEMS = 100
let NAMES: List[String] = ["Ada", "Grace"]
let LIMIT = MAX_ITEMS * 2

def is_full(count: Int) -> Bool:
    return count >= LIMIT
