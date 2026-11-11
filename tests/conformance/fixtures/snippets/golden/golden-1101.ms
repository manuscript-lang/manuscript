// conform: tags=diagnostics
// conform: phase=check
fn work() Int:
    if tagged_detail(integer) != "integer 7" or tagged_detail(text) != "text diagnostic":
        return 1
    return 0
