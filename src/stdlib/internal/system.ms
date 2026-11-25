import (
	CpuInfo,
	MemoryUsage,
	NetworkInterface,
	RuntimeCounts,
	SystemInfo,
	UserInfo from "@std/os/system.ms",
	Duration from "@std/time.ms",
)

// The host's memory, uptime, load, and parallelism numbers in one flat record;
// `metrics` shapes it into `SystemMetrics`.
export type MetricsSnapshot {
	total_memory, free_memory, available_memory, uptime_nanos Int
	load_1, load_5, load_15 Float
	available_parallelism Int
}

export extern fn msstd_system_endianness() move String

export extern fn msstd_system_end_of_line() move String

export extern fn msstd_system_dev_null() move String

// The case index of `Os`: 0 Linux, 1 Macos, 2 Windows, 3 Other.
export extern fn msstd_system_os() Int

export extern fn msstd_system_constants() move Map[String, Int]

export extern fn msstd_system_info() move SystemInfo

export extern fn msstd_system_user_info() move UserInfo!

export extern fn msstd_system_network_interfaces() move List[NetworkInterface]!

export extern fn msstd_system_cpus() move List[CpuInfo]!

export extern fn msstd_system_metrics() move MetricsSnapshot!

export extern fn msstd_system_hostname() move String!

export extern fn msstd_system_machine() move String!

export extern fn msstd_system_os_release() move String!

export extern fn msstd_system_os_version() move String!

export extern fn msstd_system_home_directory() move String!

export extern fn msstd_system_get_priority(pid Int) Int!

export extern fn msstd_system_set_priority(pid, priority Int) Void!

export extern fn msstd_process_available_memory() Int!

export extern fn msstd_process_constrained_memory() Int!

export extern fn msstd_process_elapsed() Duration!

export extern fn msstd_process_memory_usage() move MemoryUsage!

export extern fn msstd_process_runtime_counts() move RuntimeCounts!
