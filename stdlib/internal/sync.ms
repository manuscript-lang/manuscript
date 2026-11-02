export extern fn msrt_channel_token() Int

export extern fn msrt_channel_park(token: Int) Unit

export extern fn msrt_waitq_push(key: Int, token: Int) Unit

export extern fn msrt_waitq_wake(key: Int) Int

export extern fn msrt_waitq_remove(key: Int, token: Int) Int
