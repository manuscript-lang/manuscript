export extern fn msstd_time_duration_add(value: Int, other: Int) Int

export extern fn msstd_time_duration_subtract(value: Int, other: Int) Int

export extern fn msstd_time_duration_multiply(value: Int, factor: Int) Int

export extern fn msstd_time_duration_divide(value: Int, divisor: Int) Int

export extern fn msstd_time_duration_negate(value: Int) Int

export extern fn msstd_time_duration_abs(value: Int) Int

export extern fn msstd_time_duration_to_microseconds(value: Int) Int

export extern fn msstd_time_duration_to_milliseconds(value: Int) Int

export extern fn msstd_time_duration_to_seconds(value: Int) Float

export extern fn msstd_time_duration_to_minutes(value: Int) Float

export extern fn msstd_time_duration_to_hours(value: Int) Float

export extern fn msstd_time_local_zone() String

export extern fn msstd_time_sleep(duration: Int) Unit
