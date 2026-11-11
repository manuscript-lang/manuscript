// conform: tags=diagnostics
// conform: phase=check
if line := read_line(input, max_bytes: 100):
        return line.is_some()
    return false