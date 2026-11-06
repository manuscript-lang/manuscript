import Bytes from "@std/bytes.ms"
import (
    CommandOutput,
    CpuUsage,
    NativeSignals,
    NativeSubprocess,
    ProcessInfo,
    ResourceUsage,
    Stdio,
    Subprocess
) from "@std/os/process.ms"
import Duration from "@std/os/time.ms"

export extern fn msstd_process_command_run(
    program: String,
    arguments: List[String],
    input: Bytes,
    max_output_bytes: Int?,
    timeout: Duration?,
    cwd: String?,
    env_names: List[String],
    env_values: List[String]
) CommandOutput!

export extern fn msstd_process_command_spawn(
    program: String,
    arguments: List[String],
    stdin: Stdio,
    stdout: Stdio,
    stderr: Stdio,
    cwd: String?,
    env_names: List[String],
    env_values: List[String]
) Subprocess!

// The runtime stream-table id of the child's pipe: 0 stdin, 1 stdout, 2 stderr; -1 when there is no pipe.
export extern fn msstd_process_subprocess_stream_id(
    handle: NativeSubprocess,
    which: Int
) Int

export extern fn msstd_process_subprocess_wait(
    handle: NativeSubprocess,
    timeout: Duration?
) Int!

export extern fn msstd_process_subprocess_max_resident(handle: NativeSubprocess) Int

export extern fn msstd_process_subprocess_terminate(handle: NativeSubprocess) Unit

export extern fn msstd_process_subprocess_kill(handle: NativeSubprocess) Unit

export extern fn msstd_process_subprocess_close(handle: NativeSubprocess) Unit

export extern fn msstd_process_cpu_usage() CpuUsage!

export extern fn msstd_process_groups() List[Int]!

export extern fn msstd_process_initialize_groups(username: String, gid: Int) Unit!

export extern fn msstd_process_resource_usage() ResourceUsage!

export extern fn msstd_process_send_signal(pid: Int, signal: Int) Unit!

export extern fn msstd_process_set_groups(groups: List[Int]) Unit!

export extern fn msstd_process_set_identity(kind: String, id: Int) Unit!

export extern fn msstd_process_set_title(title: String) Unit!

export extern fn msstd_process_title() String!

export extern fn msstd_process_umask(mask: Int) Int!

export extern fn msstd_process_watch_signals(
    signals: List[Int],
    capacity: Int?
) NativeSignals!

export extern fn msstd_process_signal_next(signals: NativeSignals) Int!

export extern fn msstd_process_signal_close(signals: NativeSignals) Unit

export extern fn msstd_system_get_priority(pid: Int) Int!

export extern fn msstd_system_set_priority(pid: Int, priority: Int) Unit!

export extern fn msstd_process_replace(
    program: String,
    arguments: List[String],
    env_names: List[String],
    env_values: List[String]
) Unit!

export extern fn msstd_process_info() ProcessInfo!
