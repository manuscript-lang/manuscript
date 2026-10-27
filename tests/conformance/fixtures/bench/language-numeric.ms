# conform: tags=control-flow,faults,modules,mutation,stdlib-collections,stdlib-faults,tier-stdlib
# conform: phase=run
# conform: origin=bench/language/numeric.ms
from "@std/core.ms" import panic

export def main() -> Int:
    var sum = 0
    for i in 0..5000000:
        if i % 100 >= 48: sum += 1
    if sum != 2600000: return panic("numeric checksum")

    return 0
