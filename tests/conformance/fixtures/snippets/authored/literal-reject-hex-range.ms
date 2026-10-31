# conform: tags=numbers,diagnostics,tier-core
# conform: phase=check
# conform: origin=hex literal range
export fn main() Int:
    let x = 0xFFFF_FFFF_FFFF_FFFF
    return x
