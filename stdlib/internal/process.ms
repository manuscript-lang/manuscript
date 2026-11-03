import (Commands, NativeSubprocess, ProcessControl, System) from "@std/os/process.ms"
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
