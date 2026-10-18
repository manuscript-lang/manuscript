import range from "@std/collections.ms"
import Closeable from "@std/cleanup.ms"

type Resource:
    value: Int

impl Closeable for Resource:
    fn close() Unit: return

fn empty(value: Int) Int: value

fn kept(resource: Resource) Int:
    with active = resource: return 1

fn ints(left: Int, right: Int, limit: Int, resource: Resource) Int:
    with active = resource:
        var count = 0
        for index in range(0, limit):
            if left == right: count += 1
        return count

fn floats(left: Float, right: Float, limit: Int, resource: Resource) Int:
    with active = resource:
        var count = 0
        for index in range(0, limit):
            if left == right: count += 1
        return count

fn bools(left: Bool, right: Bool, limit: Int, resource: Resource) Int:
    with active = resource:
        var count = 0
        for index in range(0, limit):
            if left == right: count += 1
        return count

fn strings(left: String, right: String, limit: Int, resource: Resource) Int:
    with active = resource:
        var count = 0
        for index in range(0, limit):
            if left == right: count += 1
        return count
