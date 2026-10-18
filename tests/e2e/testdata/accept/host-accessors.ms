import {arguments, environment} from "@std/cli.ms"
import {stdin, stdout, stderr} from "@std/io.ms"
import {clock, wall_clock} from "@std/time.ms"
import entropy from "@std/random.ms"
import system from "@std/system.ms"
import network from "@std/net.ms"
import panic from "@std/faults.ms"
import TaskGroup from "@std/tasks.ms"

fn check_services() Unit:
    if arguments().length() != 0:
        return panic("test arguments are not empty")

    let before = clock().now()
    let after = clock().now()
    if after - before < 0.milliseconds:
        return panic("clock roots changed")
    if wall_clock().now().unix_seconds() <= 0:
        return panic("wall clock unavailable")
    if system().info().cpu_count <= 0:
        return panic("system service unavailable")

    for entry in environment():
        match system().environment(entry.key):
            some(value):
                if value != entry.value:
                    return panic("environment snapshot differs")
            none:
                return panic("environment entry missing")

    match entropy().bytes(count: 0):
        ok(data):
            if data.length() != 0:
                return panic("unexpected entropy size")
        error(_):
            return panic("entropy unavailable")

test "host accessors work in callbacks and task executions":
    let check = check_services
    check()

    with group = TaskGroup():
        group.start(check)
        group.start(check)

        match group.join():
            ok(_):
                return
            error(_):
                return panic("task host access failed")

test "repeated accessors retain closed root state":
    stdin().close()
    stdout().close()
    stderr().close()
    network().close()

    let cause = match stdout().write("".to_bytes()):
        ok(_):
            return panic("accessor reopened stdout")
        error(cause): cause

    match cause:
        Closed:
            return
        _:
            return panic("unexpected closed-stream error")

test "a later test receives fresh standard output":
    match stdout().write("".to_bytes()):
        ok(_):
            return
        error(_):
            return panic("another test closed this test's stdout")
