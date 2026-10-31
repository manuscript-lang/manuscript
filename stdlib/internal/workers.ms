import Bytes from "@std/bytes.ms"

export extern fn msrt_pipe_new() Int

export extern fn msrt_pipe_peer(end: Int) Int

export extern fn msrt_pipe_send(end: Int, message: String) Int

export extern fn msrt_pipe_send_bytes(end: Int, message: Bytes) Int

export extern fn msrt_pipe_close(end: Int) Unit

export extern fn msrt_worker_start(entry: fn() Unit, end: Int) Int

export extern fn msrt_worker_end() Int

export extern fn msrt_worker_cancel(handle: Int) Unit

export extern fn msrt_worker_wait(handle: Int) String
