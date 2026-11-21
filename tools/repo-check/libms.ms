// libms entry points for tools. Link `target/libms_tools.a` (`make libms-tools`).

// The canonical syntax-tree dump of `text` (see src/compiler/include/ms/libms.h), an
// `error ...` line when it does not parse, or "" when it is not valid UTF-8.
export extern fn ms_tool_syntax_dump(path: String, text: String) String
