# conform: tags=closures,stdlib-tasks,tier-stdlib
# conform: phase=run
from "@std/channels.ms" import Channel
from "@std/io.ms" import stdout
from "@std/tasks.ms" import TaskGroup

type Hook:
    run: Callable[[Int], Int]

def twice(f: Callable[[Int], Int]) -> Int:
    let g = f.clone()
    return f(1) + g(2)

export def main() -> Int:
    let base = 5
    let entry: Callable[[Channel[Unit, Unit]], Int] = lambda ch: base + 1
    let xs = [10, 20, 30]
    let pick: Callable[[Int], Int] = lambda i: xs[i]
    let hook = Hook(run: pick.clone())

    with let g = TaskGroup[Int]():
        g.spawn(entry.clone())
        g.spawn(entry.clone())
        g.spawn(entry)

        let total = g.results().get(List[Int]())
        let _ = stdout().write(
            "tasks " + total.length().to_string() + " first " + total[
                0
            ].to_string() + "\n"
        )

    let _ = stdout().write(
        "pick " + pick(0).to_string() + " hook " + hook.run(
            1
        ).to_string() + " twice " + twice(pick).to_string() + "\n"
    )
    return 0
