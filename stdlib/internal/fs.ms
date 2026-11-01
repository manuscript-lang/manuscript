export extern fn msstd_fs_constants() Map[String, Int]

export extern fn msrt_path_basename(path: String) String

export extern fn msrt_path_dirname(path: String) String

export extern fn msrt_path_extension(path: String) String

export extern fn msrt_path_is_absolute(path: String) Bool

export extern fn msrt_path_join(parts: List[String]) String

export extern fn msrt_path_normalize(path: String) String

export extern fn msrt_path_basename_without(path: String, suffix: String) String

export extern fn msrt_path_separator() String

export extern fn msrt_path_delimiter() String

export extern fn msrt_path_to_namespaced_path(path: String) String
