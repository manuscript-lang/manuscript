// conform: tags=diagnostics
// conform: phase=check
interface Read:
    fn get() Int
fn old(value: Read & Equal) Unit:
    return
