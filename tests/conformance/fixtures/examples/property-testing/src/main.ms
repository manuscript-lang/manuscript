from "@std/io.ms" import stdout

# Returns the numbers in ascending order, keeping duplicates.
export def insertion_sort(numbers: List[Int]) -> List[Int]:
    var sorted: List[Int] = []

    for n in numbers:
        var at = sorted.length()
        while at > 0 and sorted[at - 1] > n:
            at -= 1
        sorted.insert(at, n)

    return sorted

export def main() -> Int:
    stdout().write(f"{insertion_sort([3, 1, 2]).join(",")}\n").get()
    return 0
