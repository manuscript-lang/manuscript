// conform: tags=diagnostics
// conform: phase=check
enum Other:
    Missing(value: Int)
fn other() Other: Other.Missing(1)
fn standard() MissingValue: MissingValue.Missing("location")
fn read(value: Other) Int:
    match value:
        Missing(found): return found
