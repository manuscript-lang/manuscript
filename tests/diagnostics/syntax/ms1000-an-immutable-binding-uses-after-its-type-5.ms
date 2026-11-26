// conform: tags=diagnostics
// conform: phase=check
    let invalid =
    return 1
// expect-error: MS1000 3:17-3:18 an immutable binding uses ':=' after its type: write 'x Type := value'; '=' binds only after 'var'
// expect-fix: 3:17-3:18 ":="
