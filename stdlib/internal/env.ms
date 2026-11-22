export extern fn msrt_args() move List[String]

export extern fn msstd_process_change_directory(path: String) Void!

export extern fn msstd_process_environment_map() move Map[String, String]!

export extern fn msstd_process_environment_is_set(name: String) Bool

export extern fn msstd_process_set_environment(name: String, value: String?) Void!

export extern fn msstd_process_working_directory() move String!

export extern fn msstd_system_home_directory() move String!
