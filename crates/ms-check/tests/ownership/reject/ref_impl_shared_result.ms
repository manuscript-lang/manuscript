import {new_lock, Lock} from "@std/lock.ms"

interface Cell:
    fn get() ref Lock[List[String]]

type Fresh:
    n: Int

# A `Lock` handle is `Copy` but holds a reference, so it is not exempt like a scalar.
impl Cell for Fresh:
    fn get() Lock[List[String]]:  # error: implements an operation declared `ref`
        return new_lock(["a"])
