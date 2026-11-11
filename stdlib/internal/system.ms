import (
	CpuInfo,
	MemoryUsage,
	NetworkInterface,
	SystemInfo,
	UserInfo from "@std/os/system.ms",
	Duration from "@std/time.ms",
)

// The host's memory, uptime, load, and parallelism numbers in one flat record;
// `metrics` shapes it into `SystemMetrics`.
export type MetricsSnapshot:
	total_memory: Int
	free_memory: Int
	available_memory: Int
	uptime_nanos: Int
	load_1: Float
	load_5: Float
	load_15: Float
	available_parallelism: Int

export extern fn msstd_system_endianness() String

export extern fn msstd_system_end_of_line() String

export extern fn msstd_system_dev_null() String

// The case index of `Os`: 0 Linux, 1 Macos, 2 Windows, 3 Other.
export extern fn msstd_system_os() Int

export extern fn msstd_system_constants() Map[String, Int]

export extern fn msstd_system_info() SystemInfo

export extern fn msstd_system_user_info() UserInfo!

export extern fn msstd_system_network_interfaces() List[NetworkInterface]!

export extern fn msstd_system_cpus() List[CpuInfo]!

export extern fn msstd_system_metrics() MetricsSnapshot!

export extern fn msstd_system_hostname() String!

export extern fn msstd_system_machine() String!

export extern fn msstd_system_os_release() String!

export extern fn msstd_system_os_version() String!

export extern fn msstd_system_home_directory() String!

export extern fn msstd_system_get_priority(pid: Int) Int!

export extern fn msstd_system_set_priority(pid: Int, priority: Int) Unit!

export extern fn msstd_process_available_memory() Int!

export extern fn msstd_process_constrained_memory() Int!

export extern fn msstd_process_elapsed() Duration!

export extern fn msstd_process_memory_usage() MemoryUsage!
