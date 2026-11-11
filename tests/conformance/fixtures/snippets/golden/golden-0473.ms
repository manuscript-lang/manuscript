// conform: tags=diagnostics
// conform: phase=check
enum Other:
    Missing(value: Int)
fn get() Other: Missing(1)
