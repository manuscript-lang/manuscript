import {arguments, control} from "@std/process.ms"
import {IoError, stdin, stdout, stderr} from "@std/io.ms"
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
    if control().environment().is_error():
        return panic("environment unavailable")

    if let data = entropy().bytes(0):
        if data.length() != 0:
            return panic("unexpected entropy size")
    else:
        return panic("entropy unavailable")

test "host accessors work in callbacks and task executions":
    let check = check_services
    check()

    with group = TaskGroup():
        group.start(check)
        group.start(check)
        if group.join().is_error():
            return panic("task host access failed")

test "repeated accessors retain closed root state":
    stdin().close()
    stdout().close()
    stderr().close()
    network().close()
    let written = stdout().write("")
    if written.is_ok():
        return panic("accessor reopened stdout")
    if written.err() != IoError.Closed:
        return panic("unexpected closed-stream error")

test "a later test receives fresh standard output":
    if stdout().write("").is_error():
        return panic("another test closed this test's stdout")
