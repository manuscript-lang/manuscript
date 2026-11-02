import Bytes from "@std/bytes.ms"
import ReadStream, WriteStream from "@std/io/io.ms"
import CommandError, Stdio from "@std/os/process.ms"
import NativeLink, NativeProcess from "@std/os/processes.ms"

export extern fn msrt_obj_share[T](value: T) T

export extern fn msstd_process_fork(
    runner: fn() Unit,
    stdin: Stdio,
    stdout: Stdio,
    stderr: Stdio
) NativeProcess!CommandError

export extern fn msstd_process_forked_link(process: NativeProcess) NativeLink

export extern fn msstd_process_forked_stdin(process: NativeProcess) WriteStream

export extern fn msstd_process_forked_output(
    process: NativeProcess,
    which: Int
) ReadStream

export extern fn msstd_process_forked_wait(
    process: NativeProcess,
    timeout_ns: Int
) Int!CommandError

export extern fn msstd_process_forked_signal(process: NativeProcess, force: Bool) Unit

export extern fn msstd_process_forked_close(process: NativeProcess) Unit

export extern fn msstd_process_ipc_child() NativeLink

export extern fn msstd_process_ipc_read(link: NativeLink, max: Int) Bytes

export extern fn msstd_process_ipc_wait_reader(link: NativeLink) Bool

export extern fn msstd_process_ipc_write(link: NativeLink, data: Bytes) Bool

export extern fn msstd_process_ipc_close(link: NativeLink) Unit
