// conform: tags=diagnostics
// conform: phase=check
"
fn use() Int {
    match fail() {
        error(NotFound) => return 1
        ok(value) => return value
    }
}
fn record(value: Item?) Int {
    match value {
        item => return Item.value
        null => return 0
    }
}
// expect-error: MS1001 3:1 unterminated text literal; text must close with '"' on the same line, so add the quote or write \\n for a line break
// expect-error: MS1000 10:16-10:17 remove the ':' between 'value' and its type; write value Type
// expect-fix: 10:16-10:17 ""
