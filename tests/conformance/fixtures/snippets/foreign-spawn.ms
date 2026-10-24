# conform: tags=diagnostics,stdlib-tasks,tier-core
# conform: phase=check
# conform: origin=foreign-syntax diagnostics
def f() -> Unit:
    spawn(lambda: 1)
