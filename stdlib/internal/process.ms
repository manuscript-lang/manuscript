import ReadStream, WriteStream from "@std/io/io.ms"
import (
    CommandError,
    Commands,
    NativeSubprocess,
    ProcessControl,
    System
) from "@std/os/process.ms"
import Duration from "@std/os/time.ms"

export extern fn msrt_args() List[String]

export extern fn msstd_system_endianness() String

export extern fn msstd_system_end_of_line() String

export extern fn msstd_system_dev_null() String

export extern fn msstd_system_os_type() String

export extern fn msstd_system_constants() Map[String, Int]

export extern fn msstd_process_commands() Commands

export extern fn msstd_process_control() ProcessControl

export extern fn msstd_process_system() System

export extern fn msstd_process_subprocess_stdin(handle: NativeSubprocess) WriteStream

export extern fn msstd_process_subprocess_stream(
    handle: NativeSubprocess,
    which: Int
) ReadStream

export extern fn msstd_process_subprocess_wait(
    handle: NativeSubprocess,
    timeout: Duration?
) Int!CommandError

export extern fn msstd_process_subprocess_max_resident(handle: NativeSubprocess) Int

export extern fn msstd_process_subprocess_terminate(handle: NativeSubprocess) Unit

export extern fn msstd_process_subprocess_kill(handle: NativeSubprocess) Unit

export extern fn msstd_process_subprocess_close(handle: NativeSubprocess) Unit
