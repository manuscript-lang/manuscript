// conform: tags=diagnostics
// conform: phase=check
fn use(value: Int?) Int:
    present := match value:
        n: n
        none: return 0
    return match value:
        n: present + n
        none: 0
