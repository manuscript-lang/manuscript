// conform: tags=diagnostics
// conform: phase=check
if line := read_line(input):
        size := line.get().byte_length()
        return size > 0
    return false