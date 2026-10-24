from "@std/io.ms" import stdout
from "@std/queue.ms" import Queue
from "@math" import total
from "@math" import compute

type Package:
    title: String
    count: Int

# A real entry point: records, generics, a local queue, and a native workload.
export def main() -> Int:
    let package = Package("Manuscript", 42)
    let values = [10, 20, 30]
    let optional = Optional[Int].some(5)

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
    let output = f"{package.title}: {sum}; checksum {checksum}\n"
    if stdout().write(output).is_error():
        return 1

    return 0
