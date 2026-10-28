from "@std/core.ms" import Closeable

type Resource:
    value: Int

impl Closeable for Resource:
    def close() -> Unit: return

def empty(value: Int) -> Int: value

def kept(resource: Resource) -> Int:
    with let active = resource: return 1

def ints(left: Int, right: Int, limit: Int, resource: Resource) -> Int:
    with let active = resource:
        var count = 0
        for index in 0..limit:
            if left == right: count += 1
        return count

def floats(left: Float, right: Float, limit: Int, resource: Resource) -> Int:
    with let active = resource:
        var count = 0
        for index in 0..limit:
            if left == right: count += 1
        return count

def bools(left: Bool, right: Bool, limit: Int, resource: Resource) -> Int:
    with let active = resource:
        var count = 0
        for index in 0..limit:
            if left == right: count += 1
        return count

def strings(left: String, right: String, limit: Int, resource: Resource) -> Int:
    with let active = resource:
        var count = 0
        for index in 0..limit:
            if left == right: count += 1
        return count
