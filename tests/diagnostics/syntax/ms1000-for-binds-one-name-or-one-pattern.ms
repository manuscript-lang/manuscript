// conform: tags=diagnostics
// conform: phase=check
fn f() Int {
    for i, x in [1] {
        return i
    }
    return 0
}
// expect-error: MS1000 4:10-4:11 for binds one name or one pattern; to read positions, loop over the entries, e.g. 'for entry in items.entries() { ... }' and use entry.index and entry.value (a Map's entries() give entry.key and entry.value), or destructure each element with 'for [a, b] in pairs { ... }'
