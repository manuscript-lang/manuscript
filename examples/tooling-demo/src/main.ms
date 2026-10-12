import Process from "@std/cli.ms"
import List from "@std/collections.ms"
import Optional from "@std/optional.ms"
import Queue from "@std/queues.ms"
import total from "@math"
import compute from "@math"

type Package:
    title: String
    count: Int

# A real entry point: records, generics, a bounded service, and a native workload.
export fn main(process: Process) -> Int:
    let package = Package(title: "Manuscript", count: 42)
    let values = [10, 20, 30]
    let optional = Optional[Int].some(value: 5)
    match optional:
        some(value):
            if value != 5:
                return 1
        none:
            return 1
    let sum = total(first: values.length(), second: 20, third: 30)
    with queue = Queue[Int](capacity: 4):
        let admitted = queue.send(value: package.count)
        match admitted:
            error(_):
                return 1
            ok(_):
                let checksum = compute(iterations: 3000000)
                let output = "{package.title}: {sum}; checksum {checksum}\n"
                match process.stdout.write(data: output.to_bytes()):
                    ok(_):
                        return 0
                    error(_):
                        return 1
