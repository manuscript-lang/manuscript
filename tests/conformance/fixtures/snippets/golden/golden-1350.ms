// conform: tags=diagnostics
// conform: phase=check
"
fn use() Int:
    match fail():
        error(NotFound): return 1
        ok(value): return value
fn record(value: Item?) Int:
    match value:
        item: return Item.value
        none: return 0
