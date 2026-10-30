import stdout from "@std/io.ms"
import Queue from "@std/queue.ms"
import total from "@math"
import compute from "@math"

type Package:
    title: String
    count: Int

# A real entry point: records, generics, a local queue, and a native workload.
export fn main() Int:
    let package = Package("Manuscript", 42)
    let values = [10, 20, 30]
    let optional = Int?.some(5)

    if let value = optional:
        if value != 5:
            return 1
    else:
        return 1

    let sum = total(values.length(), 20, 30)
    var queue = Queue[Int](4)
    if not queue.enqueue(package.count):
        return 1

    let checksum = compute(3000000)
    let output = "{package.title}: {sum}; checksum {checksum}\n"
    if stdout().write(output).is_error():
        return 1

    return 0
