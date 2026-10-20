//! Standard-library interfaces implemented by runtime handles: `stdin()`, `files()`, ...
//!
//! The interface value's data is a refcounted runtime handle (or nothing). Each interface
//! operation becomes a generated forwarder that calls the runtime symbol named by [`METHODS`]
//! through the same marshalling as any native method, so statuses become `Result` values.

use crate::Error;
use crate::cx::{Cx, Job, JobKind};
use crate::func::{FnLower, Val};
use crate::native::NArg;
use crate::text::runtime_fn;
use ms_check::hir::ModuleHir;
use ms_check::types as ct;
use ms_mir::builder::FuncBuilder;
use ms_mir::ir::{FuncId, FuncKind, Imm, Linkage, Mode, Module, Op, Param, VtableDef, VtableId};
use ms_mir::types::{IfaceId, Ty as MTy, TyKind};
use std::rc::Rc;

/// Native functions that return an interface over a runtime handle: the function, the
/// interface module, and the runtime call that makes the handle with its constant argument.
pub(crate) const HANDLE_FUNCTIONS: &[(&str, &str, &str, i64)] = &[
    ("io/stdin", "io", "msstd_io_standard", 0),
    // No handle: the interface value carries nothing and its operations open handles.
    ("io/files", "io", "", 0),
    ("fs/filesystem", "fs", "", 0),
    ("process/commands", "process", "", 0),
    ("process/control", "process", "", 0),
    ("system/system", "system", "", 0),
    ("terminal/terminal", "terminal", "", 0),
    ("time/clock", "time", "", 0),
    ("time/wall_clock", "time", "", 0),
    // The rules are the table: `path_win` forwards with the Windows flag set.
    ("random/entropy", "random", "", 0),
    ("path/posix", "path", "", 0),
    ("path/win32", "path_win", "", 0),
    ("net/network", "net", "msrt_net_network", 0),
];

/// Interfaces whose values carry no data.
const UNIT_DATA: &[(&str, &str)] = &[
    ("io", "Files"),
    ("fs", "FileSystem"),
    ("process", "Commands"),
    ("process", "ProcessControl"),
    ("system", "System"),
    ("terminal", "Terminal"),
    ("time", "Clock"),
    ("time", "WallClock"),
    ("random", "Entropy"),
    ("path", "PathOperations"),
    ("path_win", "PathOperations"),
];

/// A constant argument the runtime symbol takes after the operation's own.
#[derive(Clone, Copy)]
enum Extra {
    Bool(bool),
    Int(i64),
}

/// One row of `METHODS`: module, interface, operation, runtime symbol, constant extras.
type MethodRow = (
    &'static str,
    &'static str,
    &'static str,
    &'static str,
    &'static [(&'static str, Extra)],
);

const METHODS: &[MethodRow] = &[
    (
        "net",
        "Network",
        "bind_datagram",
        "msrt_net_network_bind_datagram",
        &[],
    ),
    ("net", "Network", "close", "msrt_net_network_close", &[]),
    ("net", "Network", "connect", "msrt_net_network_connect", &[]),
    (
        "net",
        "Network",
        "connect_unix",
        "msrt_net_network_connect_unix",
        &[],
    ),
    ("net", "Network", "listen", "msrt_net_network_listen", &[]),
    (
        "net",
        "Network",
        "listen_unix",
        "msrt_net_network_listen_unix",
        &[],
    ),
    (
        "net",
        "Network",
        "restrict",
        "msrt_net_network_restrict",
        &[],
    ),
    (
        "net",
        "Network",
        "with_resolver",
        "msrt_net_network_with_resolver",
        &[],
    ),
    ("net", "Network", "lookup", "msrt_net_network_lookup", &[]),
    (
        "net",
        "Connection",
        "close",
        "msrt_net_connection_close",
        &[],
    ),
    (
        "net",
        "Connection",
        "local_address",
        "msrt_net_connection_local_address",
        &[],
    ),
    (
        "net",
        "Connection",
        "peer_address",
        "msrt_net_connection_peer_address",
        &[],
    ),
    ("net", "Connection", "read", "msrt_net_connection_read", &[]),
    (
        "net",
        "Connection",
        "write",
        "msrt_net_connection_write",
        &[],
    ),
    (
        "net",
        "Connection",
        "write_bytes",
        "msrt_net_connection_write_bytes",
        &[],
    ),
    (
        "net",
        "Connection",
        "shutdown_write",
        "msrt_net_connection_shutdown_write",
        &[],
    ),
    ("net", "Listener", "accept", "msrt_net_listener_accept", &[]),
    (
        "net",
        "Listener",
        "address",
        "msrt_net_listener_address",
        &[],
    ),
    ("net", "Listener", "close", "msrt_net_listener_close", &[]),
    (
        "net",
        "DatagramSocket",
        "address",
        "msrt_net_datagram_address",
        &[],
    ),
    (
        "net",
        "DatagramSocket",
        "close",
        "msrt_net_datagram_close",
        &[],
    ),
    (
        "net",
        "DatagramSocket",
        "receive",
        "msrt_net_datagram_receive",
        &[],
    ),
    (
        "net",
        "DatagramSocket",
        "send",
        "msrt_net_datagram_send",
        &[],
    ),
    (
        "net",
        "DatagramSocket",
        "send_bytes",
        "msrt_net_datagram_send_bytes",
        &[],
    ),
    (
        "net",
        "Network",
        "http_client",
        "msrt_net_network_http_client",
        &[],
    ),
    ("net", "Network", "request", "msrt_net_network_request", &[]),
    (
        "net",
        "Network",
        "request_bytes",
        "msrt_net_network_request_bytes",
        &[],
    ),
    ("net", "Network", "serve", "msrt_net_network_serve", &[]),
    (
        "net",
        "Network",
        "serve_stream",
        "msrt_net_network_serve_stream",
        &[],
    ),
    ("net", "HttpClient", "close", "msrt_http_client_close", &[]),
    (
        "net",
        "HttpClient",
        "request",
        "msrt_http_client_request",
        &[],
    ),
    (
        "net",
        "HttpClient",
        "request_bytes",
        "msrt_http_client_request_bytes",
        &[],
    ),
    (
        "net",
        "HttpClient",
        "request_stream",
        "msrt_http_client_request_stream",
        &[],
    ),
    (
        "net",
        "HttpServer",
        "address",
        "msrt_http_server_address",
        &[],
    ),
    ("net", "HttpServer", "close", "msrt_http_server_close", &[]),
    ("net", "HttpServer", "wait", "msrt_http_server_wait", &[]),
    ("http", "ResponseBody", "close", "msrt_http_body_close", &[]),
    (
        "http",
        "ResponseBody",
        "metadata",
        "msrt_http_body_metadata",
        &[],
    ),
    ("http", "ResponseBody", "read", "msrt_http_body_read", &[]),
    (
        "http",
        "HttpExchange",
        "close",
        "msrt_http_exchange_close",
        &[],
    ),
    (
        "http",
        "HttpExchange",
        "headers",
        "msrt_http_exchange_headers",
        &[],
    ),
    (
        "http",
        "HttpExchange",
        "method",
        "msrt_http_exchange_method",
        &[],
    ),
    (
        "http",
        "HttpExchange",
        "path",
        "msrt_http_exchange_path",
        &[],
    ),
    (
        "http",
        "HttpExchange",
        "protocol",
        "msrt_http_exchange_protocol",
        &[],
    ),
    (
        "http",
        "HttpExchange",
        "query",
        "msrt_http_exchange_query",
        &[],
    ),
    (
        "http",
        "HttpExchange",
        "read",
        "msrt_http_exchange_read",
        &[],
    ),
    (
        "http",
        "HttpExchange",
        "send_headers",
        "msrt_http_exchange_send_headers",
        &[],
    ),
    (
        "http",
        "HttpExchange",
        "write",
        "msrt_http_exchange_write",
        &[],
    ),
    (
        "http",
        "HttpExchange",
        "write_bytes",
        "msrt_http_exchange_write_bytes",
        &[],
    ),
    ("io", "Files", "open", "msstd_io_open", &[]),
    ("random", "Entropy", "bytes", "msstd_random_os_bytes", &[]),
    ("io", "File", "read", "msstd_io_read", &[]),
    ("io", "File", "close", "msstd_io_close", &[]),
    ("io", "ReadStream", "read", "msstd_io_read", &[]),
    ("io", "ReadStream", "close", "msstd_io_close", &[]),
    ("io", "WriteStream", "write", "msstd_io_write", &[]),
    (
        "io",
        "WriteStream",
        "write_bytes",
        "msstd_io_write_bytes",
        &[],
    ),
    ("io", "WriteStream", "flush", "msstd_io_flush", &[]),
    ("io", "WriteStream", "close", "msstd_io_close", &[]),
    ("fs", "FileSystem", "open_flags", "msstd_fs_file_open", &[]),
    (
        "fs",
        "FileSystem",
        "canonicalize",
        "msstd_fs_canonicalize",
        &[],
    ),
    ("fs", "FileSystem", "copy_file", "msstd_fs_copy_file", &[]),
    (
        "fs",
        "FileSystem",
        "create_directory",
        "msstd_fs_create_directory",
        &[],
    ),
    (
        "fs",
        "FileSystem",
        "create_link",
        "msstd_fs_create_link",
        &[],
    ),
    ("fs", "FileSystem", "read_file", "msstd_fs_read_file", &[]),
    ("fs", "FileSystem", "read_link", "msstd_fs_read_link", &[]),
    ("fs", "FileSystem", "remove", "msstd_fs_remove", &[]),
    ("fs", "FileSystem", "rename", "msstd_fs_rename", &[]),
    (
        "fs",
        "FileSystem",
        "temporary_root",
        "msstd_fs_temporary_root",
        &[],
    ),
    (
        "fs",
        "FileSystem",
        "temporary_directory",
        "msstd_fs_temporary_directory",
        &[],
    ),
    ("fs", "FileSystem", "write_file", "msstd_fs_write_file", &[]),
    (
        "fs",
        "FileSystem",
        "write_file_bytes",
        "msstd_fs_write_file",
        &[],
    ),
    ("fs", "FileSystem", "access", "msstd_fs_access", &[]),
    (
        "fs",
        "FileSystem",
        "append_file",
        "msstd_fs_append_file",
        &[],
    ),
    (
        "fs",
        "FileSystem",
        "append_file_bytes",
        "msstd_fs_append_file",
        &[],
    ),
    (
        "fs",
        "FileSystem",
        "chmod",
        "msstd_fs_chmod",
        &[("follow", Extra::Bool(true))],
    ),
    (
        "fs",
        "FileSystem",
        "chmod_link",
        "msstd_fs_chmod",
        &[("follow", Extra::Bool(false))],
    ),
    ("fs", "FileSystem", "chown", "msstd_fs_chown", &[]),
    ("fs", "FileSystem", "truncate", "msstd_fs_truncate", &[]),
    ("fs", "FileSystem", "hard_link", "msstd_fs_hard_link", &[]),
    ("fs", "FileSystem", "copy_tree", "msstd_fs_copy_tree", &[]),
    ("fs", "FileSystem", "glob", "msstd_fs_glob", &[]),
    (
        "fs",
        "FileSystem",
        "open_directory",
        "msstd_fs_directory_open",
        &[],
    ),
    (
        "fs",
        "FileSystem",
        "temporary",
        "msstd_fs_temporary_open",
        &[],
    ),
    ("fs", "FileSystem", "open", "msstd_fs_open", &[]),
    ("fs", "FileHandle", "reader", "msstd_fs_file_reader", &[]),
    ("fs", "FileHandle", "writer", "msstd_fs_file_writer", &[]),
    ("fs", "FileHandle", "close", "msstd_io_close", &[]),
    ("fs", "FileHandle", "read", "msstd_io_read", &[]),
    ("fs", "FileHandle", "write", "msstd_io_write", &[]),
    ("fs", "FileHandle", "append_file", "msstd_io_write", &[]),
    (
        "fs",
        "FileHandle",
        "append_file_bytes",
        "msstd_io_write_bytes",
        &[],
    ),
    (
        "fs",
        "FileHandle",
        "write_bytes",
        "msstd_io_write_bytes",
        &[],
    ),
    ("fs", "FileHandle", "read_at", "msstd_fs_file_read_at", &[]),
    (
        "fs",
        "FileHandle",
        "write_at",
        "msstd_fs_file_write_at",
        &[],
    ),
    (
        "fs",
        "FileHandle",
        "write_at_bytes",
        "msstd_fs_file_write_at",
        &[],
    ),
    (
        "fs",
        "FileHandle",
        "read_file",
        "msstd_fs_file_read_file",
        &[],
    ),
    (
        "fs",
        "FileHandle",
        "read_vectors",
        "msstd_fs_file_read_vectors",
        &[],
    ),
    (
        "fs",
        "FileHandle",
        "write_vectors",
        "msstd_fs_file_write_vectors",
        &[],
    ),
    ("fs", "FileHandle", "seek", "msstd_fs_file_seek", &[]),
    (
        "fs",
        "FileHandle",
        "truncate",
        "msstd_fs_file_truncate",
        &[],
    ),
    ("fs", "FileHandle", "sync", "msstd_fs_file_sync", &[]),
    (
        "fs",
        "FileHandle",
        "data_sync",
        "msstd_fs_file_data_sync",
        &[],
    ),
    ("fs", "FileHandle", "chmod", "msstd_fs_file_chmod", &[]),
    ("fs", "FileHandle", "chown", "msstd_fs_file_chown", &[]),
    ("fs", "FileSystem", "stat", "msstd_fs_stat", &[]),
    ("fs", "FileHandle", "stat", "msstd_fs_file_stat", &[]),
    (
        "fs",
        "FileSystem",
        "glob_entries",
        "msstd_fs_glob_entries",
        &[],
    ),
    ("fs", "FileSystem", "copy", "msstd_fs_copy", &[]),
    ("fs", "FileSystem", "list", "msstd_fs_list", &[]),
    ("fs", "Directory", "read", "msstd_fs_directory_read", &[]),
    ("fs", "Directory", "path", "msstd_fs_directory_path", &[]),
    ("fs", "Directory", "close", "msstd_fs_directory_close", &[]),
    (
        "fs",
        "TemporaryDirectory",
        "path",
        "msstd_fs_temporary_path",
        &[],
    ),
    (
        "fs",
        "TemporaryDirectory",
        "close",
        "msstd_fs_temporary_close",
        &[],
    ),
    (
        "crypto",
        "Hasher",
        "update",
        "msrt_crypto_hasher_update",
        &[],
    ),
    (
        "crypto",
        "Hasher",
        "finish",
        "msrt_crypto_hasher_finish",
        &[],
    ),
    ("time", "Clock", "now", "msstd_time_clock_now", &[]),
    ("time", "WallClock", "now", "msstd_time_wall_clock_now", &[]),
    (
        "process",
        "Commands",
        "run",
        "msstd_process_command_run",
        &[],
    ),
    (
        "process",
        "Commands",
        "spawn",
        "msstd_process_command_spawn",
        &[],
    ),
    (
        "process",
        "Subprocess",
        "stdin",
        "msstd_process_subprocess_stream",
        &[("which", Extra::Int(0))],
    ),
    (
        "process",
        "Subprocess",
        "stdout",
        "msstd_process_subprocess_stream",
        &[("which", Extra::Int(1))],
    ),
    (
        "process",
        "Subprocess",
        "stderr",
        "msstd_process_subprocess_stream",
        &[("which", Extra::Int(2))],
    ),
    (
        "process",
        "Subprocess",
        "wait",
        "msstd_process_subprocess_wait",
        &[],
    ),
    (
        "process",
        "Subprocess",
        "terminate",
        "msstd_process_subprocess_terminate",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "monotonic_time",
        "msstd_process_monotonic_time",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "uptime",
        "msstd_process_elapsed",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "environment",
        "msstd_process_environment_map",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "set_environment",
        "msstd_process_set_environment",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "load_environment",
        "msstd_process_load_environment",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "working_directory",
        "msstd_process_working_directory",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "change_directory",
        "msstd_process_change_directory",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "send_signal",
        "msstd_process_send_signal",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "groups",
        "msstd_process_groups",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "umask",
        "msstd_process_umask",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "title",
        "msstd_process_title",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "set_title",
        "msstd_process_set_title",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "constrained_memory",
        "msstd_process_constrained_memory",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "available_memory",
        "msstd_process_available_memory",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "initialize_groups",
        "msstd_process_initialize_groups",
        &[],
    ),
    (
        "process",
        "ProcessControl",
        "info",
        "msstd_process_info_record",
        &[],
    ),
    ("system", "System", "info", "msstd_system_info_record", &[]),
    (
        "system",
        "System",
        "working_directory",
        "msstd_system_working_directory",
        &[],
    ),
    ("system", "System", "hostname", "msstd_system_hostname", &[]),
    (
        "system",
        "System",
        "home_directory",
        "msstd_system_home_directory",
        &[],
    ),
    (
        "system",
        "System",
        "user_info",
        "msstd_system_user_info_record",
        &[],
    ),
    (
        "system",
        "System",
        "os_release",
        "msstd_system_os_release",
        &[],
    ),
    (
        "system",
        "System",
        "os_version",
        "msstd_system_os_version",
        &[],
    ),
    ("system", "System", "machine", "msstd_system_machine", &[]),
    (
        "system",
        "System",
        "network_interfaces",
        "msstd_system_network_interfaces_records",
        &[],
    ),
    ("system", "System", "cpus", "msstd_system_cpus_records", &[]),
    (
        "system",
        "System",
        "metrics",
        "msstd_system_metrics_record",
        &[],
    ),
    (
        "system",
        "System",
        "get_priority",
        "msstd_system_get_priority",
        &[],
    ),
    (
        "system",
        "System",
        "set_priority",
        "msstd_system_set_priority",
        &[],
    ),
    (
        "terminal",
        "Terminal",
        "capabilities",
        "msstd_terminal_capabilities_record",
        &[],
    ),
    (
        "terminal",
        "Terminal",
        "size",
        "msstd_terminal_size_record",
        &[],
    ),
    (
        "terminal",
        "Terminal",
        "raw_mode",
        "msstd_terminal_raw_mode",
        &[],
    ),
    (
        "terminal",
        "RawTerminal",
        "close",
        "msstd_terminal_raw_terminal_close",
        &[],
    ),
    (
        "terminal",
        "RawTerminal",
        "next_event",
        "msstd_terminal_raw_terminal_next_event",
        &[],
    ),
    (
        "terminal",
        "RawTerminal",
        "size",
        "msstd_terminal_raw_terminal_size_record",
        &[],
    ),
    (
        "terminal",
        "RawTerminal",
        "move_cursor",
        "msstd_terminal_raw_terminal_move_cursor",
        &[],
    ),
    (
        "terminal",
        "RawTerminal",
        "show_cursor",
        "msstd_terminal_raw_terminal_show_cursor",
        &[],
    ),
    (
        "terminal",
        "RawTerminal",
        "erase",
        "msstd_terminal_raw_terminal_erase",
        &[],
    ),
    (
        "process",
        "Subprocess",
        "kill",
        "msstd_process_subprocess_kill",
        &[],
    ),
    (
        "process",
        "Subprocess",
        "close",
        "msstd_process_subprocess_close",
        &[],
    ),
];

/// The MIR type of a runtime handle object.
pub(crate) fn handle_ty(m: &mut Module) -> MTy {
    m.types.obj("Handle", Vec::new())
}

/// A generated forwarder of one interface operation.
pub(crate) struct MethodJob {
    hir: Rc<ModuleHir>,
    name: String,
    /// The runtime symbol, or none when the operation is not implemented yet.
    sym: Option<String>,
    decl: Vec<ct::Param>,
    /// Constant `Bool` arguments after the operation's own.
    extras: Vec<(&'static str, Extra)>,
    params: Vec<MTy>,
    ret: MTy,
    data_ty: MTy,
}

impl Cx {
    /// The table for `iface` as returned by the runtime symbol `sym` (named `msstd_<module>_...`).
    pub(crate) fn handle_vtable_of(
        &mut self,
        m: &mut Module,
        hir: &Rc<ModuleHir>,
        sym: &str,
        iface: IfaceId,
    ) -> Result<VtableId, Error> {
        let mut module = sym
            .strip_prefix("msstd_")
            .or_else(|| sym.strip_prefix("msrt_"))
            .and_then(|r| r.split('_').next())
            .ok_or_else(|| Error::new(format!("{sym} returns an interface")))?;
        let ity = self
            .contracts
            .get(&iface)
            .cloned()
            .ok_or_else(|| Error::new("unknown interface"))?;
        // Streams are `@std/io` handles whichever module hands them out.
        if matches!(ity.name.to_string().as_str(), "ReadStream" | "WriteStream") {
            module = "io";
        }
        self.handle_vtable(m, hir, module, &ity, iface)
    }

    /// The table of `iface` over runtime handles of `module`, one forwarder per operation.
    pub(crate) fn handle_vtable(
        &mut self,
        m: &mut Module,
        hir: &Rc<ModuleHir>,
        module: &str,
        ity: &ct::Ty,
        iface: IfaceId,
    ) -> Result<VtableId, Error> {
        let key = format!("handle:{}:{}", module, iface.0);
        if let Some(v) = self.vtables.get(&key) {
            return Ok(*v);
        }
        let iface_name = ity.name.to_string();
        let data_ty = if UNIT_DATA.contains(&(module, iface_name.as_str())) {
            MTy::UNIT
        } else {
            handle_ty(m)
        };
        let sigs = m.ifaces[iface.index()].methods.clone();
        let subst = ct::substitution(ity);
        let ops = ity
            .def
            .as_ref()
            .map(|d| d.operations.borrow().clone())
            .unwrap_or_default();
        let mut methods = Vec::new();
        for s in &sigs {
            let decl = ops
                .iter()
                .find(|op| op.name.as_str() == s.name)
                .map(|op| ct::sub(&op.ty, &subst).params.clone())
                .unwrap_or_default();
            let row = METHODS
                .iter()
                .find(|(md, i, op, ..)| *md == module && *i == iface_name && *op == s.name);
            let (sym, extras) =
                if let Some(windows) = module.strip_prefix("path").map(|r| r == "_win") {
                    // Every operation is the `msrt_path_<operation>` entry point with the rules flag.
                    (
                        Some(format!("msrt_path_{}", s.name)),
                        vec![("windows", Extra::Bool(windows))],
                    )
                } else {
                    (
                        row.map(|r| r.3.to_string()),
                        row.map(|r| r.4.to_vec()).unwrap_or_default(),
                    )
                };
            let mut ps = vec![Param {
                ty: MTy::PTR,
                mode: Mode::Borrow,
            }];
            ps.extend(s.params.iter().map(|t| Param {
                ty: *t,
                mode: Mode::Borrow,
            }));
            let mut f = ms_mir::ir::Func::new(&format!("{iface_name}.{}", s.name), ps, s.ret);
            f.kind = FuncKind::Method;
            f.linkage = Linkage::Internal;
            let id = m.add_func(f);
            self.queue.push(Job {
                func: id,
                kind: JobKind::HandleMethod(Rc::new(MethodJob {
                    hir: hir.clone(),
                    name: format!("{iface_name}.{}", s.name),
                    sym,
                    decl,
                    extras,
                    params: s.params.clone(),
                    ret: s.ret,
                    data_ty,
                })),
            });
            methods.push(id);
        }
        m.vtables.push(VtableDef {
            name: key.clone(),
            iface,
            methods,
            data_ty,
        });
        let id = VtableId(m.vtables.len() as u32 - 1);
        self.vtables.insert(key, id);
        Ok(id)
    }
}

/// Builds the body of a forwarder reserved by [`Cx::handle_vtable`].
pub(crate) fn build_method(
    cx: &mut Cx,
    m: &mut Module,
    func: FuncId,
    job: &MethodJob,
) -> Result<(), Error> {
    let proto = m.funcs[func.index()].clone();
    let b = FuncBuilder::new(m, &proto.name, proto.params.clone(), proto.ret);
    let file = 0;
    let mut fl = FnLower::new(cx, b, job.hir.clone(), Default::default(), file, job.ret);
    fl.b.func_mut().kind = FuncKind::Method;
    fl.b.func_mut().linkage = Linkage::Internal;
    let args = fl.b.params();
    let result = forward(&mut fl, job, &args);
    let mut out = fl.b.into_func();
    result?;
    out.compact_blocks();
    m.funcs[func.index()] = out;
    Ok(())
}

fn forward(fl: &mut FnLower<'_>, job: &MethodJob, args: &[ms_mir::ir::Value]) -> Result<(), Error> {
    let Some(sym) = &job.sym else {
        let msg =
            fl.b.str_lit(&format!("{} is not available in this build yet", job.name));
        let ext = runtime_fn(fl.b.m, "msrt_fault_string", &[MTy::STR], MTy::UNIT);
        fl.b.call_rt(ext, &[msg]);
        fl.b.unreachable();
        return Ok(());
    };
    // The getters of a record result take the handle too when the status call does.
    if let Some(base) = sym.strip_suffix("_record") {
        let lead: Vec<_> = takes_handle(&format!("{base}_status"))
            .then(|| load_handle(fl, job, args))
            .into_iter()
            .collect();
        let r = fl.record_getters(base, job.ret, &lead)?;
        fl.emit_return(Some(r));
        return Ok(());
    }
    if let Some(base) = sym.strip_suffix("_records") {
        let r = fl.record_list_getters(base, job.ret)?;
        fl.emit_return(Some(r));
        return Ok(());
    }
    let recv = takes_handle(sym).then(|| Val {
        v: load_handle(fl, job, args),
        own: false,
    });
    // Operations whose arguments or result do not fit the generic marshalling.
    match sym.as_str() {
        "msstd_terminal_raw_terminal_next_event" => {
            let h = load_handle(fl, job, args);
            let r = fl.terminal_next_event(sym, h, args[1], job.ret)?;
            fl.emit_return(Some(r));
            return Ok(());
        }
        "msstd_terminal_raw_terminal_erase" => {
            let h = load_handle(fl, job, args);
            let region = fl.b.alt_tag(args[1]);
            let code = fl.status_code(sym, &[h, region])?;
            let r = fl.status_result(sym, code, None, None, job.ret)?;
            fl.emit_return(Some(r));
            return Ok(());
        }
        _ => {}
    }
    let mut nargs: Vec<NArg> = job
        .decl
        .iter()
        .zip(&args[1..])
        .map(|(p, v)| NArg {
            name: p.name,
            val: Val { v: *v, own: false },
            wrapped: false,
        })
        .collect();
    debug_assert_eq!(job.params.len(), nargs.len());
    let mut decl = job.decl.clone();
    for (name, extra) in &job.extras {
        let name = ct::n(name);
        let (ty, v) = match *extra {
            Extra::Bool(b) => (ct::bool_(), fl.b.bconst(b)),
            Extra::Int(i) => (ct::int(), fl.b.iconst(i)),
        };
        // The rules flag leads a path entry point's arguments.
        let lead = sym.starts_with("msrt_path_");
        decl.insert(if lead { 0 } else { decl.len() }, ct::Param { name, ty });
        nargs.insert(
            if lead { 0 } else { nargs.len() },
            NArg {
                name,
                val: Val { v, own: false },
                wrapped: false,
            },
        );
    }
    if matches!(sym.as_str(), "msstd_fs_glob_entries" | "msstd_fs_copy") {
        let r = fl.fs_walk(sym, &decl, &nargs, job.ret)?;
        fl.emit_return(Some(r));
        return Ok(());
    }
    let r = match recv {
        Some(recv) => fl.rt_method(sym, recv, &decl, &nargs, job.ret)?,
        None => fl.rt_function(sym, &decl, &nargs, job.ret)?,
    };
    fl.emit_return(Some(r));
    Ok(())
}

/// Whether the runtime function `sym` takes the receiver's handle first.
fn takes_handle(sym: &str) -> bool {
    crate::rtcall::rt_sig(sym)
        .and_then(|s| {
            s.params
                .first()
                .map(|p| p.name == "h" || p.ty == "*const Obj")
        })
        .unwrap_or(false)
}

/// The runtime handle inside the receiver interface value `args[0]`.
fn load_handle(
    fl: &mut FnLower<'_>,
    job: &MethodJob,
    args: &[ms_mir::ir::Value],
) -> ms_mir::ir::Value {
    fl.b.emit(
        Op::Load,
        &[args[0]],
        Imm::Ty(job.data_ty),
        Some(job.data_ty),
    )
    .expect("load")
}

impl FnLower<'_> {
    /// `RawTerminal.next_event(timeout)`: the runtime answers a status and keeps the event for
    /// the `msstd_terminal_event_*` getters.
    fn terminal_next_event(
        &mut self,
        sym: &str,
        handle: ms_mir::ir::Value,
        timeout: ms_mir::ir::Value,
        result: MTy,
    ) -> Result<Val, Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new("next_event: not a Result"));
        };
        let ok = self.ok_case_index(a)?;
        let opt = self.b.m.alts[a.index()].cases[ok].fields[0].1;
        let TyKind::Opt(event) = self.b.m.types.kind(opt).clone() else {
            return Err(Error::new("next_event: not an optional event"));
        };
        let TyKind::Alt(ea) = self.b.m.types.kind(event).clone() else {
            return Err(Error::new("next_event: not an event alternative"));
        };
        let input = crate::rtcall::Input {
            val: Some(Val {
                v: timeout,
                own: false,
            }),
            wrapped: false,
        };
        let (has, nanos) = self.flatten_optional(input, "i64")?;
        let code = self.status_code(sym, &[handle, has, nanos])?;
        self.status_optional_result(sym, code, &mut |s| s.terminal_event(ea), result)
    }

    /// The `TerminalEvent` the runtime last delivered.
    fn terminal_event(&mut self, ea: ms_mir::types::AltId) -> Result<ms_mir::ir::Value, Error> {
        let case = |s: &Self, name: &str| {
            s.b.m.alts[ea.index()]
                .cases
                .iter()
                .position(|c| c.name == name)
                .map(|i| i as u32)
                .ok_or_else(|| Error::new(format!("TerminalEvent has no {name} case")))
        };
        let (text_case, key_case, resize_case) = (
            case(self, "Text")?,
            case(self, "Key")?,
            case(self, "Resize")?,
        );
        let ty = self.b.m.types.alt(ea);
        let kind = self.getter_call("msstd_terminal_event_kind", MTy::INT, &[])?;
        let zero = self.b.iconst(0);
        let is_text = self.b.icmp(ms_mir::ir::Cc::Eq, kind, zero);
        let r = self.two_ways(
            is_text,
            ty,
            &mut |s| {
                let text = s.getter_call("msstd_terminal_event_text", MTy::STR, &[])?;
                Ok(Some(s.b.alt_new(ea, text_case, &[text])))
            },
            &mut |s| {
                let one = s.b.iconst(1);
                let is_key = s.b.icmp(ms_mir::ir::Cc::Eq, kind, one);
                let r = s.two_ways(
                    is_key,
                    ty,
                    &mut |s| {
                        let name = s.getter_call("msstd_terminal_event_text", MTy::STR, &[])?;
                        let ctrl = s.getter_call("msstd_terminal_event_ctrl", MTy::BOOL, &[])?;
                        let alt = s.getter_call("msstd_terminal_event_alt", MTy::BOOL, &[])?;
                        let shift = s.getter_call("msstd_terminal_event_shift", MTy::BOOL, &[])?;
                        Ok(Some(s.b.alt_new(ea, key_case, &[name, ctrl, alt, shift])))
                    },
                    &mut |s| {
                        let columns =
                            s.getter_call("msstd_terminal_event_columns", MTy::INT, &[])?;
                        let rows = s.getter_call("msstd_terminal_event_rows", MTy::INT, &[])?;
                        Ok(Some(s.b.alt_new(ea, resize_case, &[columns, rows])))
                    },
                )?;
                Ok(Some(r.v))
            },
        )?;
        Ok(r.v)
    }

    /// `stdin()`: an interface value over a runtime handle made by `make(constant)`.
    pub(crate) fn handle_interface(
        &mut self,
        e: &ms_syntax::ast::Expr,
        module: &str,
        make: &str,
        constant: i64,
    ) -> Result<Val, Error> {
        let ity = self.ety(e);
        let want = self.emty(e)?;
        let TyKind::Iface(iface) = self.b.m.types.kind(want).clone() else {
            return Err(Error::new("a handle function must return an interface"));
        };
        let hir = self.hir.clone();
        let vt = self.cx.handle_vtable(self.b.m, &hir, module, &ity, iface)?;
        let h = if make.is_empty() {
            self.b.unit()
        } else {
            let ht = handle_ty(self.b.m);
            // A constructor that takes no argument ignores the constant.
            let takes_constant = crate::rtcall::rt_sig(make).is_some_and(|s| !s.params.is_empty());
            let k = takes_constant.then(|| self.b.iconst(constant));
            self.call_runtime(make, k.as_slice(), ht)?
        };
        let v = self
            .b
            .emit(Op::IfaceNew, &[h], Imm::Vtable(vt), Some(want))
            .expect("iface");
        Ok(Val { v, own: true })
    }
}

impl FnLower<'_> {
    /// `io.read_line(input, max_bytes)`: a runtime call over the handle behind a native
    /// `ReadStream`; other implementations are read byte by byte through their `read`.
    pub(crate) fn read_line_native(
        &mut self,
        e: &ms_syntax::ast::Expr,
        view: &ms_check::hir::CallView<'_>,
        params: &[ct::Param],
    ) -> Result<Val, Error> {
        let args = self.native_args(view)?;
        if self.dead {
            return Ok(self.dummy(MTy::UNIT));
        }
        let result = self.emty(e)?;
        let stream = params
            .iter()
            .find(|p| p.name.as_str() == "input")
            .ok_or_else(|| Error::new("read_line without an input"))?;
        let input = args
            .iter()
            .find(|a| a.name.as_str() == "input")
            .ok_or_else(|| Error::new("read_line without an input"))?;
        let TyKind::Iface(iface) = self.mty_kind(&stream.ty)? else {
            return Err(Error::new("read_line input is not an interface"));
        };
        let hir = self.hir.clone();
        let vt = self
            .cx
            .handle_vtable(self.b.m, &hir, "io", &stream.ty, iface)?;
        let stream_v = self.borrow(input.val);
        let is_handle = self
            .b
            .emit(Op::IfaceIs, &[stream_v], Imm::Vtable(vt), Some(MTy::BOOL));
        let is_handle = is_handle.expect("iface.is");
        let max: Vec<NArg> = args
            .iter()
            .filter(|a| a.name.as_str() == "max_bytes")
            .copied()
            .collect();
        let decl: Vec<ct::Param> = params
            .iter()
            .filter(|p| p.name.as_str() == "max_bytes")
            .cloned()
            .collect();
        let ht = handle_ty(self.b.m);
        self.two_ways(
            is_handle,
            result,
            &mut |s| {
                let data =
                    s.b.emit(Op::IfaceData, &[stream_v], Imm::None, Some(MTy::PTR))
                        .expect("iface.data");
                let h =
                    s.b.emit(Op::Load, &[data], Imm::Ty(ht), Some(ht))
                        .expect("load");
                let recv = Val { v: h, own: false };
                s.rt_method("msstd_io_read_line", recv, &decl, &max, result)
                    .map(|r| Some(s.owned(r)))
            },
            &mut |s| {
                let (has, n) = s.optional_int(max.first().copied())?;
                let line = crate::streamloop::Loop::ReadLine;
                s.stream_loop(line, stream_v, None, has, n, result)
                    .map(|r| Some(s.owned(r)))
            },
        )
    }

    fn mty_kind(&mut self, t: &ct::Ty) -> Result<TyKind, Error> {
        let m = self.mty(t)?;
        Ok(self.b.m.types.kind(m).clone())
    }
}

impl FnLower<'_> {
    /// A record (or `Result` of one) built from one runtime getter per field, `<base>_<name>`.
    /// An optional `<base>_status` call runs first: a nonzero status is the error case. `lead`
    /// are the leading arguments of every call (the handle of a handle method).
    pub(crate) fn record_getters(
        &mut self,
        base: &str,
        result: MTy,
        lead: &[ms_mir::ir::Value],
    ) -> Result<Val, Error> {
        let (alt, rec_ty) = match self.b.m.types.kind(result).clone() {
            TyKind::Alt(a) => {
                let ok = self.ok_case_index(a)?;
                (
                    Some((a, ok)),
                    self.b.m.alts[a.index()].cases[ok].fields[0].1,
                )
            }
            _ => (None, result),
        };
        let TyKind::Rec(rid) = self.b.m.types.kind(rec_ty).clone() else {
            return Err(Error::new(format!("{base}: not a record result")));
        };
        let build = |s: &mut Self| -> Result<ms_mir::ir::Value, Error> {
            let rec = s.record_from_getters(base, rid, lead)?;
            Ok(match alt {
                Some((a, ok)) => s.b.alt_new(a, ok as u32, &[rec]),
                None => rec,
            })
        };
        let status = format!("{base}_status");
        if alt.is_none() || crate::rtcall::rt_sig(&status).is_none() {
            let v = build(self)?;
            return Ok(Val { v, own: true });
        }
        let code = self.status_code(&status, lead)?;
        let zero = self.b.iconst(0);
        let good = self.b.icmp(ms_mir::ir::Cc::Eq, code, zero);
        self.two_ways(good, result, &mut |s| build(s).map(Some), &mut |s| {
            s.status_failure(result, code, &status).map(Some)
        })
    }

    /// A `Result` of a list of records read from a runtime snapshot: `<base>_status` takes it,
    /// `<base>_count` sizes it and each field comes from `<base>_<name>(index)`.
    pub(crate) fn record_list_getters(&mut self, base: &str, result: MTy) -> Result<Val, Error> {
        let TyKind::Alt(a) = self.b.m.types.kind(result).clone() else {
            return Err(Error::new(format!("{base}: not a Result")));
        };
        let ok = self.ok_case_index(a)?;
        let list_ty = self.b.m.alts[a.index()].cases[ok].fields[0].1;
        let TyKind::List(rec_ty) = self.b.m.types.kind(list_ty).clone() else {
            return Err(Error::new(format!("{base}: not a list result")));
        };
        let TyKind::Rec(rid) = self.b.m.types.kind(rec_ty).clone() else {
            return Err(Error::new(format!("{base}: not a list of records")));
        };
        let status = format!("{base}_status");
        let code = self.status_code(&status, &[])?;
        let zero = self.b.iconst(0);
        let good = self.b.icmp(ms_mir::ir::Cc::Eq, code, zero);
        self.two_ways(
            good,
            result,
            &mut |s| {
                let n = s.call_runtime(&format!("{base}_count"), &[], MTy::INT)?;
                let empty = s.b.list_new(rec_ty, n);
                let acc = s.b.declare_var(list_ty, Mode::Own);
                s.b.def_var(acc, empty);
                let idx = s.b.declare_var(MTy::INT, Mode::Borrow);
                let start = s.b.iconst(0);
                s.b.def_var(idx, start);
                let (header, body, exit) = (s.b.new_block(), s.b.new_block(), s.b.new_block());
                s.b.br(header, &[]);
                s.b.switch_to(header);
                let i = s.b.use_var(idx);
                let more = s.b.icmp(ms_mir::ir::Cc::Lt, i, n);
                s.b.br_if(more, body, &[], exit, &[]);
                s.b.seal_block(body);
                s.b.switch_to(body);
                let i = s.b.use_var(idx);
                let rec = s.record_from_getters(base, rid, &[i])?;
                let cur = s.b.use_var(acc);
                let next = s.b.list_push(cur, rec);
                s.b.def_var(acc, next);
                let one = s.b.iconst(1);
                let i = s.b.use_var(idx);
                let after = s.b.binop(Op::IAdd, i, one);
                s.b.def_var(idx, after);
                s.b.br(header, &[]);
                s.b.seal_block(header);
                s.b.seal_block(exit);
                s.b.switch_to(exit);
                let list = s.b.use_var(acc);
                Ok(Some(s.b.alt_new(a, ok as u32, &[list])))
            },
            &mut |s| s.status_failure(result, code, &status).map(Some),
        )
    }

    /// The record `rid` with each field read by the getter `<base>_<field>`, called with `lead`
    /// (the item index of a list, or the handle).
    fn record_from_getters(
        &mut self,
        base: &str,
        rid: ms_mir::types::RecId,
        lead: &[ms_mir::ir::Value],
    ) -> Result<ms_mir::ir::Value, Error> {
        let fields = self.b.m.records[rid.index()].fields.clone();
        let mut values = Vec::new();
        for (name, ty) in &fields {
            let sym = format!("{base}_{name}");
            let v = self.getter_field(&sym, *ty, lead)?;
            values.push(self.owned(v));
        }
        Ok(self.b.rec_new(rid, &values))
    }

    /// One record field: scalars and strings come straight from the getter, a payload-free enum
    /// from its case index, and a `List[Float]` (the three load averages) from `sym(window)`.
    fn getter_field(
        &mut self,
        sym: &str,
        ty: MTy,
        lead: &[ms_mir::ir::Value],
    ) -> Result<Val, Error> {
        match self.b.m.types.kind(ty).clone() {
            TyKind::Alt(a) => {
                let code = self.getter_call(sym, MTy::INT, lead)?;
                let v = self.enum_from_index(a, code, 0)?;
                Ok(Val { v, own: true })
            }
            TyKind::List(e) if e == MTy::FLOAT => {
                let three = self.b.iconst(3);
                let mut list = self.b.list_new(e, three);
                for window in 0..3 {
                    let w = self.b.iconst(window);
                    let x = self.call_runtime(sym, &[w], MTy::FLOAT)?;
                    list = self.b.list_push(list, x);
                }
                Ok(Val { v: list, own: true })
            }
            _ => {
                let v = self.getter_call(sym, ty, lead)?;
                Ok(Val { v, own: true })
            }
        }
    }

    /// Calls the getter `sym` with `lead`. A `Bool` crosses as a `u8` of which only the low byte
    /// is defined.
    fn getter_call(
        &mut self,
        sym: &str,
        ty: MTy,
        lead: &[ms_mir::ir::Value],
    ) -> Result<ms_mir::ir::Value, Error> {
        if lead.is_empty() {
            return Ok(self.rt_function(sym, &[], &[], ty)?.v);
        }
        if ty != MTy::BOOL {
            return self.call_runtime(sym, lead, ty);
        }
        let raw = self.call_runtime(sym, lead, MTy::INT)?;
        let mask = self.b.iconst(0xff);
        let low = self.b.binop(Op::And, raw, mask);
        let zero = self.b.iconst(0);
        Ok(self.b.icmp(ms_mir::ir::Cc::Ne, low, zero))
    }
}
