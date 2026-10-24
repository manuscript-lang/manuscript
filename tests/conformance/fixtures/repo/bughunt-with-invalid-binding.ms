# conform: tags=diagnostics,with-cleanup,tier-core
# conform: phase=check
export def main() -> Int:
    with try 5 as g:
        return 1
    return 0
