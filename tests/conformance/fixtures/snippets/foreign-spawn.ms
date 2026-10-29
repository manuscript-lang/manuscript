# conform: tags=diagnostics,stdlib-tasks,tier-core
# conform: phase=check
# conform: origin=foreign-syntax diagnostics
fn f() Unit:
    spawn(fn: 1)
