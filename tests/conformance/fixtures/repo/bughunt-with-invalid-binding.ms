# conform: tags=diagnostics,with-cleanup,tier-core
# conform: phase=check
export fn main() Int:
    with g = try 5:
        return 1
    return 0
