import stdout from "@std/io.ms"

# Returns the numbers in ascending order, keeping duplicates.
export fn insertion_sort(numbers: List[Int]) List[Int]:
    var sorted: List[Int] = []

    for n in numbers:
        var at = sorted.length()
        while at > 0 and sorted[at - 1] > n:
            at -= 1
        sorted.insert(at, n)

    return sorted

export fn main() Int:
    stdout().write("{insertion_sort([3, 1, 2]).join(",")}\n").get()
    return 0
