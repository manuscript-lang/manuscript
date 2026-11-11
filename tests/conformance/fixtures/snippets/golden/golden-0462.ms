// conform: tags=diagnostics
// conform: phase=check
enum Other:
    OutOfRange
fn other() Other: Other.OutOfRange
fn standard() CollectionError: CollectionError.OutOfRange
fn recognize(value: Other) Int:
    match value:
        OutOfRange: return 1
