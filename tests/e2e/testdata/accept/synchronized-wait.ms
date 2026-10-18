import Synchronized from "@std/sync.ms"
import TaskGroup from "@std/tasks.ms"
import panic from "@std/faults.ms"

fn wait_until_ready(ready: Synchronized[Bool]) -> Bool:
    with locked = ready.lock():
        while not locked.get():
            locked.wait()
        return locked.get()

fn mark_ready(ready: Synchronized[Bool]) -> Unit:
    with locked = ready.lock():
        locked.set(true)
        locked.notify_all()

test "wait returns after another task notifies":
    let ready = Synchronized(false)

    with group = TaskGroup():
        let waiter = group.start(fn(): wait_until_ready(ready: ready))
        mark_ready(ready: ready)

        match waiter.join():
        ok(seen):
            if not seen:
                return panic(message: "waiter woke before the value changed")
        error(_):
            return panic(message: "waiter failed")

test "group close cancels a waiting task":
    let ready = Synchronized(false)
    with group = TaskGroup():
        group.start(fn(): wait_until_ready(ready: ready))
