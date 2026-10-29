import Decimal from "@std/decimal.ms"
import arguments from "@std/process.ms"
import clock from "@std/time.ms"
import stdout from "@std/io.ms"

export fn main() Int:
    let args = arguments()
    let operation = args[0]
    let count = args[1].parse_int().get()
    let seed = args[2].parse_int().get()
    let timer = clock()
    var result = seed.to_decimal() / 100d
    var unsigned: UInt64 = 18446744073709551615
    if operation == "uint" and seed != 0:
        unsigned = seed.to_uint64().get()
    let start = timer.now()
    if operation == "int":
        for i in 0..count:
            result = (seed + i % 10000).to_decimal()
    else if operation == "uint":
        for i in 0..count:
            result = (unsigned - (i % 10000).to_uint64().get()).to_decimal()
    else if operation == "stream":
        var total = 0
        for i in 0..count:
            total += (i % 10000).to_decimal().truncate_to_int().get()
        result = total.to_decimal()
    else if operation == "negate":
        for i in 0..count:
            result = -result
    else:
        return 2
    let elapsed = timer.now().difference(start).to_nanoseconds()
    stdout().write("operation={operation} count={count} seed={seed} ns={elapsed} result={result}\n").get()
    if operation == "int":
        if result != (seed + (count - 1) % 10000).to_decimal():
            return 1
        return 0
    if operation == "uint":
        if result != (unsigned - ((count - 1) % 10000).to_uint64().get()).to_decimal():
            return 1
        return 0
    if operation == "stream":
        let complete = count / 10000
        let remainder = count % 10000
        let expected = complete * 49995000 + remainder * (remainder - 1) / 2
        if result != expected.to_decimal():
            return 1
        return 0
    var expected = seed.to_decimal() / 100d
    if count % 2 != 0:
        expected = -expected
    if result != expected:
        return 1
    return 0
