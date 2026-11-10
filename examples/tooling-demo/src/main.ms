import (
	stdout from "@std/io/io.ms",
	Queue from "@std/collections/queue.ms",
	total from "@math",
	compute from "@math",
)

type Package:
	title: String
	count: Int

// A real entry point: records, generics, a local queue, and a native workload.
fn main() Int:
	package := Package("Manuscript", 42)
	values := [10, 20, 30]
	optional: Int? = 5

	if value := optional:
		if value != 5: return 1
	else:
		return 1

	sum := total(values.length(), 20, 30)
	var queue = Queue[Int](4)
	if not queue.enqueue(package.count): return 1

	checksum := compute(3000000)
	output := "{package.title}: {sum}; checksum {checksum}\n"
	if stdout().write(output).is_error(): return 1

	return 0
