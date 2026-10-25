from "@std/shared.ms" import share, Shared

interface Cell:
    def get() -> ref Shared[List[String]]

type Fresh:
    n: Int

# A `Shared` handle is `Copy` but holds a reference, so it is not exempt like a scalar.
impl Cell for Fresh:
    def get() -> Shared[List[String]]:  # error: implements an operation declared `ref`
        return share(["a"])
