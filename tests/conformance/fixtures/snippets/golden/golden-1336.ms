// conform: tags=diagnostics
// conform: phase=check
type Item:
    value: Int
fn use(value: Item?) Int:
    match value:
        item: return Item.value
        none: return 0
