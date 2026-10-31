import basename from "@std/fs.ms"

# The only way application code reaches the file system module.
export fn report_name(path: String) String:
    return basename(path)
