import stdout from "@std/io.ms"
import Queue from "@std/queues.ms"
import total from "@math"
import compute from "@math"

type Package:
    title: String
    count: Int

# A real entry point: records, generics, a local queue, and a native workload.
export fn main() Int:
    let package = Package(title: "Manuscript", count: 42)
    let values = [10, 20, 30]
    let optional = Optional[Int].some(5)

    if let value = optional:
        if value != 5:
            return 1
    else:
        return 1

    let sum = total(first: values.length(), second: 20, third: 30)
    let queue = Queue[Int](capacity: 4)
    if not queue.enqueue(package.count):
        return 1

    let checksum = compute(iterations: 3000000)
    let output = "{package.title}: {sum}; checksum {checksum}\n"

    match stdout().write(data: output.to_bytes()):
        ok(_):
            return 0
        error(_):
            return 1
