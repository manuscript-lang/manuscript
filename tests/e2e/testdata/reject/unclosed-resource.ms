from "@std/tasks.ms" import TaskGroup

# A resource that no `with` closes, nothing closes by hand and nothing takes over leaks.
export def main() -> Int:
    let group = TaskGroup[Int]()
    group.spawn(lambda ch: 1)
    return 0
