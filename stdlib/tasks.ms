from "@std/collections.ms" import range
from "@std/core.ms" import Closeable, panic
from "@std/shared.ms" import Shared, share

extern def msrt_tasks_spawn(work: Callable[[], Unit]) -> Int

extern def msrt_tasks_join(handle: Int) -> Bool

extern def msrt_tasks_cancel(handle: Int) -> Unit

# The started tasks of a group. Internal state.
export type GroupState[T]:
    # Handles of started tasks that have not been joined yet.
    handles: List[Int] = []
    # One result slot per started task, in start order: empty until the task returns, then its one result.
    slots: List[Shared[List[T]]] = []

# A scope that owns the tasks started in it. Every task returns a `T` (use `Unit` for effect-only work).
# Open a group with `with`: leaving the block cancels tasks that are still running and waits for all of them.
# Call `results` before the block ends to collect the work instead of cancelling it.
# Tasks run on the one runtime thread and switch only when one waits (`results`, sleeping, I/O).
# A fault in a task ends the program. A task that captures a value owns it; return results instead of sharing them.
export type TaskGroup[T]:
    # Internal state: the group's tasks, changed through the shared handle so the group works as a `with` binding.
    state: Shared[GroupState[T]] = share(GroupState[T]())

impl TaskGroup[T]:
    # Starts `work` as a task. It first runs when the caller waits. The task owns what `work` captures.
    def spawn(work: Callable[[], T]) -> Unit:
        let slot: Shared[List[T]] = share([])
        let task_slot = slot

        let handle = msrt_tasks_spawn(
            lambda:
                let empty = task_slot.take()
                task_slot.put([work()])
        )

        var current = self.state.take()
        current.handles.append(handle)
        current.slots.append(slot)
        self.state.put(current)

    # Waits for every started task and returns their results in start order.
    # Cancelling the waiting task unwinds it; the group's `close` then cancels the tasks.
    def results() -> List[T]:
        var values = List[T]()
        let count = self.state.get().handles.length()

        for index in range(0, count):
            let handle = self.state.get().handles.get(index)
            if msrt_tasks_join(handle):
                panic("TaskGroup: a task was cancelled before it finished")

            let slot = self.state.get().slots.get(index)
            var finished = slot.take()
            if let value = finished.pop():
                values.append(value)

        let old = self.state.take()
        self.state.put(GroupState[T]())
        return values

impl Closeable for TaskGroup[T]:
    # Cancels tasks that have not been joined and waits for them to end. Safe to call again.
    var def close() -> Unit:
        let count = self.state.get().handles.length()
        for index in range(0, count):
            msrt_tasks_cancel(self.state.get().handles.get(index))
        for index in range(0, count):
            msrt_tasks_join(self.state.get().handles.get(index))

        let old = self.state.take()
        self.state.put(GroupState[T]())
