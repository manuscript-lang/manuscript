export extern fn msrt_scope_new() Int

export extern fn msrt_scope_spawn(
    scope: Int,
    work: fn() Unit,
    task_limit_ns: Int,
    scope_limit_ns: Int
) Int

export extern fn msrt_scope_contain(scope: Int) Unit

export extern fn msrt_scope_fault_message() String

export extern fn msrt_scope_started() Unit

export extern fn msrt_task_cancel_requested() Int

export extern fn msrt_scope_join(scope: Int, handle: Int, keep: Int) Int

export extern fn msrt_scope_wait(scope: Int) Int

export extern fn msrt_scope_close(scope: Int) Unit

export extern fn msrt_channel_token() Int

export extern fn msrt_channel_park(token: Int) Unit

export extern fn msrt_channel_post(token: Int) Unit

export extern fn msrt_obj_share[T](value: T) T
