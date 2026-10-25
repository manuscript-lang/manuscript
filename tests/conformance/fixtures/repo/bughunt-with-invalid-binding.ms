# conform: tags=diagnostics,with-cleanup,tier-core
# conform: phase=check
export def main() -> Int:
    with let g = try 5:
        return 1
    return 0
