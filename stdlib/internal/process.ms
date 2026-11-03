import ReadStream, WriteStream from "@std/io/io.ms"
import (
    Commands,
    CpuUsage,
    MemoryUsage,
    NativeSignals,
    NativeSubprocess,
    ResourceUsage
) from "@std/os/process.ms"
import Duration from "@std/os/time.ms"

export extern fn msrt_args() List[String]

export extern fn msstd_system_endianness() String

export extern fn msstd_system_end_of_line() String

export extern fn msstd_system_dev_null() String

export extern fn msstd_system_os_type() String

export extern fn msstd_system_constants() Map[String, Int]

export extern fn msstd_process_commands() Commands

export extern fn msstd_process_subprocess_stdin(handle: NativeSubprocess) WriteStream

export extern fn msstd_process_subprocess_stream(
    handle: NativeSubprocess,
    which: Int
) ReadStream

export extern fn msstd_process_subprocess_wait(
    handle: NativeSubprocess,
    timeout: Duration?
) Int!

export extern fn msstd_process_subprocess_max_resident(handle: NativeSubprocess) Int

export extern fn msstd_process_subprocess_terminate(handle: NativeSubprocess) Unit

export extern fn msstd_process_subprocess_kill(handle: NativeSubprocess) Unit

export extern fn msstd_process_subprocess_close(handle: NativeSubprocess) Unit

export extern fn msstd_process_available_memory() Int!

export extern fn msstd_process_change_directory(path: String) Unit!

export extern fn msstd_process_constrained_memory() Int!

export extern fn msstd_process_cpu_usage() CpuUsage!

export extern fn msstd_process_environment_map() Map[String, String]!

export extern fn msstd_process_groups() List[Int]!

export extern fn msstd_process_initialize_groups(username: String, gid: Int) Unit!

export extern fn msstd_process_load_environment(path: String, max_bytes: Int?) Unit!

export extern fn msstd_process_memory_usage() MemoryUsage!

export extern fn msstd_process_monotonic_time() Int

export extern fn msstd_process_resource_usage() ResourceUsage!

export extern fn msstd_process_send_signal(pid: Int, signal: Int) Unit!

export extern fn msstd_process_set_environment(name: String, value: String?) Unit!

export extern fn msstd_process_set_groups(groups: List[Int]) Unit!

export extern fn msstd_process_set_identity(kind: String, id: Int) Unit!

export extern fn msstd_process_set_title(title: String) Unit!

export extern fn msstd_process_title() String!

export extern fn msstd_process_umask(mask: Int) Int!

export extern fn msstd_process_elapsed() Duration!

export extern fn msstd_process_watch_signals(
    signals: List[Int],
    capacity: Int?
) NativeSignals!

export extern fn msstd_process_signal_next(signals: NativeSignals) Int!

export extern fn msstd_process_signal_close(signals: NativeSignals) Unit

export extern fn msstd_process_working_directory() String!

export extern fn msstd_system_get_priority(pid: Int) Int!

export extern fn msstd_system_home_directory() String!

export extern fn msstd_system_hostname() String!

export extern fn msstd_system_machine() String!

export extern fn msstd_system_os_release() String!

export extern fn msstd_system_os_version() String!

export extern fn msstd_system_set_priority(pid: Int, priority: Int) Unit!

export extern fn msstd_system_working_directory() String

export extern fn msstd_process_replace(
    program: String,
    arguments: List[String],
    env_names: List[String],
    env_values: List[String]
) Unit!

export extern fn msstd_process_info_pid() Int

export extern fn msstd_process_info_parent_pid() Int

export extern fn msstd_process_info_executable() String

export extern fn msstd_process_info_arguments() List[String]

export extern fn msstd_process_info_os() String

export extern fn msstd_process_info_architecture() String

export extern fn msstd_process_info_uid() Int

export extern fn msstd_process_info_gid() Int

export extern fn msstd_process_info_effective_uid() Int

export extern fn msstd_process_info_effective_gid() Int

export extern fn msstd_system_info_os() String

export extern fn msstd_system_info_architecture() String

export extern fn msstd_system_info_cpu_count() Int

export extern fn msstd_system_user_info_status() Unit!

export extern fn msstd_system_user_info_username() String

export extern fn msstd_system_user_info_uid() Int

export extern fn msstd_system_user_info_gid() Int

export extern fn msstd_system_user_info_home() String

export extern fn msstd_system_user_info_shell() String

export extern fn msstd_system_network_interfaces_status() Unit!

export extern fn msstd_system_network_interfaces_count() Int

export extern fn msstd_system_network_interfaces_name(i: Int) String

export extern fn msstd_system_network_interfaces_address(i: Int) String

export extern fn msstd_system_network_interfaces_netmask(i: Int) String

export extern fn msstd_system_network_interfaces_family(i: Int) Int

export extern fn msstd_system_network_interfaces_mac(i: Int) String

export extern fn msstd_system_network_interfaces_internal(i: Int) Bool

export extern fn msstd_system_network_interfaces_scope_id(i: Int) Int

export extern fn msstd_system_cpus_status() Unit!

export extern fn msstd_system_cpus_count() Int

export extern fn msstd_system_cpus_model(i: Int) String

export extern fn msstd_system_cpus_speed_mhz(i: Int) Int

export extern fn msstd_system_cpus_user(i: Int) Int

export extern fn msstd_system_cpus_nice(i: Int) Int

export extern fn msstd_system_cpus_system(i: Int) Int

export extern fn msstd_system_cpus_idle(i: Int) Int

export extern fn msstd_system_cpus_irq(i: Int) Int

export extern fn msstd_system_metrics_status() Unit!

export extern fn msstd_system_metrics_total_memory() Int

export extern fn msstd_system_metrics_free_memory() Int

export extern fn msstd_system_metrics_available_memory() Int

export extern fn msstd_system_metrics_uptime() Int

export extern fn msstd_system_metrics_load_average(window: Int) Float

export extern fn msstd_system_metrics_available_parallelism() Int
