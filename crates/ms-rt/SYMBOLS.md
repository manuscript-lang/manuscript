# ms-rt symbol catalogue

Generated from the `#[unsafe(no_mangle)]` items in `crates/ms-rt/src` and `crates/ms-std-*/src` by `crates/ms-rt/gen-symbols.py`; do not edit.

```text
msrt_desc_int (data)
msrt_desc_float (data)
msrt_desc_bool (data)
msrt_desc_string (data)
msrt_desc_bytes (data)
msrt_eq_enter(a: *const u8, b: *const u8) -> u8
msrt_eq_leave(_a: *const u8, _b: *const u8)
msrt_slot_drop(d: *const TypeDesc, slot: *mut u8)
msrt_slot_copy(d: *const TypeDesc, src: *const u8, dst: *mut u8)
msrt_slot_eq(d: *const TypeDesc, a: *const u8, b: *const u8) -> u8
msrt_slot_hash(d: *const TypeDesc, slot: *const u8) -> i64
msrt_hash_int(v: i64) -> i64
msrt_hash_bytes(p: *const u8, len: usize) -> i64
msrt_hash_combine(a: i64, b: i64) -> i64
msrt_call_depth (data)
msrt_cancel_flag (data)
msrt_fault(msg: *const u8, len: usize) -> !
msrt_fault_string(s: *mut ms_rt_abi::StrObj) -> !
msrt_fault_depth() -> !
msrt_index_fault(index: i64, length: i64) -> !
msrt_list_index_fault(operation: i64, index: i64, len: i64) -> !
msrt_fault_unwrap_none() -> !
msrt_fault_result_get() -> !
msrt_fault_result_err() -> !
msrt_fault_int_overflow() -> !
msrt_fault_div_zero() -> !
msrt_fault_rem_zero() -> !
msrt_fault_div_overflow(a: i64, b: i64) -> !
msrt_cleanup_push(f: CleanupFn, arg: *mut u8) -> usize
msrt_cleanup_run(handle: usize)
msrt_cancelled() -> !
msrt_io_write_stdout(s: *mut StrObj)
msrt_io_write_stderr(s: *mut StrObj)
msrt_io_flush()
rust_eh_personality()
msrt_map_new(out: *mut MapVal)
msrt_map_drop( m: *mut MapVal, kd: *const TypeDesc, vd: *const TypeDesc, )
msrt_map_copy( m: *const MapVal, kd: *const TypeDesc, vd: *const TypeDesc, out: *mut MapVal, )
msrt_map_add( m: *mut MapVal, kd: *const TypeDesc, vd: *const TypeDesc, key: *mut u8, val: *mut u8, )
msrt_map_add_default( m: *mut MapVal, kd: *const TypeDesc, vd: *const TypeDesc, key: *mut u8, val: *mut u8, )
msrt_map_remove( m: *mut MapVal, kd: *const TypeDesc, vd: *const TypeDesc, key: *const u8, )
msrt_map_contains( m: *const MapVal, kd: *const TypeDesc, vd: *const TypeDesc, key: *const u8, ) -> u8
msrt_map_get_ptr( m: *const MapVal, kd: *const TypeDesc, vd: *const TypeDesc, key: *const u8, ) -> *const u8
msrt_map_get( m: *const MapVal, kd: *const TypeDesc, vd: *const TypeDesc, key: *const u8, out: *mut u8, ) -> u8
msrt_map_clear( m: *mut MapVal, kd: *const TypeDesc, vd: *const TypeDesc, )
msrt_map_length(m: *const MapVal) -> i64
msrt_map_slot_count(m: *const MapVal) -> i64
msrt_map_entry_ptrs( m: *const MapVal, kd: *const TypeDesc, vd: *const TypeDesc, i: i64, key_out: *mut *const u8, val_out: *mut *const u8, ) -> u8
msrt_map_keys( m: *const MapVal, kd: *const TypeDesc, vd: *const TypeDesc, out: *mut VecVal, )
msrt_map_values( m: *const MapVal, kd: *const TypeDesc, vd: *const TypeDesc, out: *mut VecVal, )
msrt_map_merge( m: *mut MapVal, other: *const MapVal, kd: *const TypeDesc, vd: *const TypeDesc, )
msrt_set_add_copy( m: *mut MapVal, kd: *const TypeDesc, key: *const u8, )
msrt_set_union( a: *const MapVal, b: *const MapVal, kd: *const TypeDesc, out: *mut MapVal, )
msrt_set_intersection( a: *const MapVal, b: *const MapVal, kd: *const TypeDesc, out: *mut MapVal, )
msrt_set_difference( a: *const MapVal, b: *const MapVal, kd: *const TypeDesc, out: *mut MapVal, )
msrt_set_symmetric_difference( a: *const MapVal, b: *const MapVal, kd: *const TypeDesc, out: *mut MapVal, )
msrt_set_is_subset_of( a: *const MapVal, b: *const MapVal, kd: *const TypeDesc, ) -> u8
msrt_set_is_superset_of( a: *const MapVal, b: *const MapVal, kd: *const TypeDesc, ) -> u8
msrt_set_is_disjoint_from( a: *const MapVal, b: *const MapVal, kd: *const TypeDesc, ) -> u8
msrt_numbers_parse_int( text: *const StrObj, radix: i64, out: *mut i64, ) -> u8
msrt_numbers_parse_float(text: *const StrObj, out: *mut f64) -> u8
msrt_numbers_error_message(status: u8) -> *mut StrObj
msrt_float_to_precision( v: f64, digits: i64, out: *mut *mut StrObj, ) -> u8
msrt_float_to_exponential( v: f64, digits: i64, out: *mut *mut StrObj, ) -> u8
msrt_float_to_fixed( v: f64, digits: i64, out: *mut *mut StrObj, ) -> u8
msrt_float_truncate_to_int(v: f64, out: *mut i64) -> u8
msrt_float_compare(a: f64, b: f64) -> i64
msrt_int_compare(a: i64, b: i64) -> i64
msrt_heap_stats(out: *mut i64)
msrt_alloc(size: usize) -> *mut u8
msrt_alloc_zeroed(size: usize) -> *mut u8
msrt_realloc(p: *mut u8, size: usize) -> *mut u8
msrt_free(p: *mut u8)
msrt_retain(o: *mut Obj)
msrt_release(o: *mut Obj)
msrt_drop_slow(o: *mut Obj)
msrt_process_exit(code: i64) -> !
msrt_start_nanos() -> i64
msrt_start( main_fn: extern "C-unwind" fn() -> i64, tables: *const Tables, argc: i32, argv: *const *const u8, ) -> i32
msrt_argv(out: *mut VecVal)
msrt_args(out: *mut VecVal)
msrt_string_empty() -> *mut StrObj
msrt_string_from_bytes(ptr: *const u8, len: usize) -> *mut StrObj
msrt_string_length(s: *const StrObj) -> i64
msrt_string_scalar_length(s: *const StrObj) -> i64
msrt_string_byte_length(s: *const StrObj) -> i64
msrt_string_is_empty(s: *const StrObj) -> u8
msrt_string_get( s: *const StrObj, index: i64, default: *mut StrObj, ) -> *mut StrObj
msrt_string_scalar_at( s: *const StrObj, index: i64, has_default: u8, default: i64, ) -> i64
msrt_string_eq(a: *const StrObj, b: *const StrObj) -> u8
msrt_string_compare(a: *const StrObj, b: *const StrObj) -> i64
msrt_string_contains(a: *const StrObj, v: *const StrObj) -> u8
msrt_string_starts_with(a: *const StrObj, v: *const StrObj) -> u8
msrt_string_ends_with(a: *const StrObj, v: *const StrObj) -> u8
msrt_string_index_of( a: *const StrObj, v: *const StrObj, out: *mut i64, ) -> u8
msrt_string_last_index_of( a: *const StrObj, v: *const StrObj, out: *mut i64, ) -> u8
msrt_string_concat( a: *const StrObj, b: *const StrObj, ) -> *mut StrObj
msrt_string_reverse(a: *const StrObj) -> *mut StrObj
msrt_string_trim(s: *const StrObj) -> *mut StrObj
msrt_string_trim_start(s: *const StrObj) -> *mut StrObj
msrt_string_trim_end(s: *const StrObj) -> *mut StrObj
msrt_string_upper(s: *const StrObj) -> *mut StrObj
msrt_string_lower(s: *const StrObj) -> *mut StrObj
msrt_string_repeat( s: *const StrObj, count: i64, has_max: u8, max: i64, out: *mut *mut StrObj, ) -> u8
msrt_string_replace_first( s: *const StrObj, old: *const StrObj, new: *const StrObj, has_max: u8, max: i64, ) -> *mut StrObj
msrt_string_replace( s: *const StrObj, old: *const StrObj, new: *const StrObj, has_max: u8, max: i64, ) -> *mut StrObj
msrt_string_replace_n( s: *const StrObj, old: *const StrObj, new: *const StrObj, max: i64, ) -> *mut StrObj
msrt_string_replace_all( s: *const StrObj, old: *const StrObj, new: *const StrObj, has_max: u8, max: i64, out: *mut *mut StrObj, ) -> u8
msrt_string_pad_start( s: *const StrObj, target: i64, padding: *const StrObj, has_max: u8, max: i64, out: *mut *mut StrObj, ) -> u8
msrt_string_pad_end( s: *const StrObj, target: i64, padding: *const StrObj, has_max: u8, max: i64, out: *mut *mut StrObj, ) -> u8
msrt_string_slice_scalars( s: *const StrObj, start: i64, end: i64, out: *mut *mut StrObj, ) -> u8
msrt_string_slice( s: *const StrObj, start: i64, end: i64, out: *mut *mut StrObj, ) -> u8
msrt_string_chars(s: *const StrObj, out: *mut VecVal)
msrt_string_lines(s: *const StrObj, out: *mut VecVal)
msrt_string_split( s: *const StrObj, sep: *const StrObj, has_max: u8, max: i64, out: *mut VecVal, )
msrt_string_scalar_values(s: *const StrObj, out: *mut VecVal)
msrt_string_from_scalars( values: *const VecVal, out: *mut *mut StrObj, ) -> u8
msrt_string_to_bytes(s: *const StrObj, out: *mut VecVal)
msrt_string_parse_int(s: *const StrObj, out: *mut i64) -> u8
msrt_string_normalize( s: *const StrObj, form: *const StrObj, has_max: u8, max: i64, out: *mut *mut StrObj, ) -> u8
msrt_string_normalize_kind( s: *const StrObj, kind: i64, has_max: u8, max: i64, out: *mut *mut StrObj, ) -> u8
msrt_int_to_string(v: i64) -> *mut StrObj
msrt_float_to_string(v: f64) -> *mut StrObj
msrt_bool_to_string(v: u8) -> *mut StrObj
msrt_int_to_string_radix(v: i64, radix: i64) -> *mut StrObj
msrt_string_quote(s: *const StrObj) -> *mut StrObj
msrt_list_new(out: *mut VecVal)
msrt_list_with_capacity( d: *const TypeDesc, cap: i64, out: *mut VecVal, )
msrt_list_drop(v: *mut VecVal, d: *const TypeDesc)
msrt_list_copy( v: *const VecVal, d: *const TypeDesc, out: *mut VecVal, )
msrt_list_push(v: *mut VecVal, d: *const TypeDesc, e: *const u8)
msrt_list_reserve(v: *mut VecVal, d: *const TypeDesc, extra: i64)
msrt_list_at( v: *const VecVal, d: *const TypeDesc, index: i64, default: *const u8, ) -> *const u8
msrt_list_get( v: *const VecVal, d: *const TypeDesc, index: i64, default: *const u8, out: *mut u8, )
msrt_list_first( v: *const VecVal, d: *const TypeDesc, out: *mut u8, ) -> u8
msrt_list_last( v: *const VecVal, d: *const TypeDesc, out: *mut u8, ) -> u8
msrt_list_index_of( v: *const VecVal, d: *const TypeDesc, probe: *const u8, out: *mut i64, ) -> u8
msrt_list_last_index_of( v: *const VecVal, d: *const TypeDesc, probe: *const u8, out: *mut i64, ) -> u8
msrt_list_contains( v: *const VecVal, d: *const TypeDesc, probe: *const u8, ) -> u8
msrt_list_prepend( v: *mut VecVal, d: *const TypeDesc, e: *const u8, )
msrt_list_insert( v: *mut VecVal, d: *const TypeDesc, index: i64, e: *const u8, )
msrt_list_pop( v: *mut VecVal, d: *const TypeDesc, out: *mut u8, ) -> u8
msrt_list_shift( v: *mut VecVal, d: *const TypeDesc, out: *mut u8, ) -> u8
msrt_list_set( v: *mut VecVal, d: *const TypeDesc, index: i64, e: *const u8, )
msrt_list_remove(v: *mut VecVal, d: *const TypeDesc, index: i64)
msrt_list_reverse_in_place(v: *mut VecVal, d: *const TypeDesc)
msrt_list_reversed( v: *const VecVal, d: *const TypeDesc, out: *mut VecVal, )
msrt_list_splice( v: *mut VecVal, d: *const TypeDesc, start: i64, count: i64, replacement: *mut VecVal, )
msrt_list_fill( v: *mut VecVal, d: *const TypeDesc, value: *const u8, start: i64, end: i64, )
msrt_list_copy_within( v: *mut VecVal, d: *const TypeDesc, target: i64, start: i64, end: i64, )
msrt_list_slice( v: *const VecVal, d: *const TypeDesc, start: i64, end: i64, out: *mut VecVal, ) -> u8
msrt_list_take( v: *const VecVal, d: *const TypeDesc, count: i64, out: *mut VecVal, )
msrt_list_drop_n( v: *const VecVal, d: *const TypeDesc, count: i64, out: *mut VecVal, )
msrt_list_concat( a: *const VecVal, b: *const VecVal, d: *const TypeDesc, out: *mut VecVal, )
msrt_list_extend( v: *mut VecVal, d: *const TypeDesc, other: *mut VecVal, )
msrt_list_flatten( lists: *const VecVal, d: *const TypeDesc, out: *mut VecVal, )
msrt_list_distinct( v: *const VecVal, d: *const TypeDesc, out: *mut VecVal, )
msrt_list_keys(v: *const VecVal, out: *mut VecVal)
msrt_list_join( v: *const VecVal, sep: *const StrObj, out: *mut *mut StrObj, )
msrt_list_sort_in_place( v: *mut VecVal, d: *const TypeDesc, cmp: CmpFn, env: *mut u8, )
msrt_list_sorted( v: *const VecVal, d: *const TypeDesc, cmp: CmpFn, env: *mut u8, out: *mut VecVal, )
msrt_list_filled( value: *const u8, d: *const TypeDesc, count: i64, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msrt_list_range(start: i64, end: i64, out: *mut VecVal)
msrt_list_range_by( start: i64, end: i64, step: i64, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msrt_list_to_set( v: *const VecVal, d: *const TypeDesc, out: *mut MapVal, )
msrt_fault_destructure(names: i64, elements: i64) -> !
msrt_bytes_drop(b: *mut VecVal)
msrt_bytes_copy(b: *const VecVal, out: *mut VecVal)
msrt_bytes_contains(b: *const VecVal, v: *const VecVal) -> u8
msrt_bytes_index_of( b: *const VecVal, v: *const VecVal, out: *mut i64, ) -> u8
msrt_bytes_last_index_of( b: *const VecVal, v: *const VecVal, out: *mut i64, ) -> u8
msrt_bytes_starts_with(b: *const VecVal, v: *const VecVal) -> u8
msrt_bytes_ends_with(b: *const VecVal, v: *const VecVal) -> u8
msrt_bytes_get( b: *const VecVal, index: i64, has_default: u8, default: i64, ) -> i64
msrt_bytes_slice( b: *const VecVal, start: i64, end: i64, out: *mut VecVal, ) -> u8
msrt_bytes_reversed(b: *const VecVal, out: *mut VecVal)
msrt_bytes_with_value( b: *const VecVal, index: i64, value: i64, out: *mut VecVal, )
msrt_bytes_concat( a: *const VecVal, b: *const VecVal, out: *mut VecVal, )
msrt_bytes_split( b: *const VecVal, sep: *const VecVal, has_max: u8, max: i64, out: *mut VecVal, )
msrt_bytes_values(b: *const VecVal, out: *mut VecVal)
msrt_bytes_from_values(values: *const VecVal, out: *mut VecVal)
msrt_bytes_decode_utf8(b: *const VecVal) -> *mut StrObj
msrt_bytes_append(b: *mut VecVal, value: i64)
msrt_bytes_extend(b: *mut VecVal, values: *const VecVal)
msrt_strbuilder_append(b: *mut VecVal, s: *const StrObj)
msrt_strbuilder_freeze(b: *mut VecVal) -> *mut StrObj
msrt_strbuilder_drop(b: *mut VecVal)
msrt_hash_list(v: *const VecVal, d: *const TypeDesc) -> i64
msstd_fs_failure_message() -> *mut StrObj
msstd_fs_read_file( path: *const StrObj, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msstd_fs_write_file( path: *const StrObj, data: *const VecVal, replace: u8, ) -> u8
msstd_fs_append_file(path: *const StrObj, data: *const VecVal) -> u8
msstd_fs_copy_file( source: *const StrObj, destination: *const StrObj, replace: u8, has_max: u8, max: i64, ) -> u8
msstd_fs_stat(path: *const StrObj, follow: u8, out: *mut InfoOut) -> u8
msstd_fs_list( path: *const StrObj, has_limit: u8, limit: i64, names: *mut VecVal, flags: *mut VecVal, ) -> u8
msstd_fs_create_directory(path: *const StrObj, recursive: u8) -> u8
msstd_fs_remove(path: *const StrObj, recursive: u8) -> u8
msstd_fs_rename(source: *const StrObj, destination: *const StrObj) -> u8
msstd_fs_read_link(path: *const StrObj, out: *mut *mut StrObj) -> u8
msstd_fs_create_link(path: *const StrObj, target: *const StrObj) -> u8
msstd_fs_hard_link( source: *const StrObj, destination: *const StrObj, ) -> u8
msstd_fs_canonicalize(path: *const StrObj, out: *mut *mut StrObj) -> u8
msstd_fs_temporary_root() -> *mut StrObj
msstd_fs_temporary_directory( pattern: *const StrObj, out: *mut *mut StrObj, ) -> u8
msstd_fs_stat_filesystem(path: *const StrObj, out: *mut FsOut) -> u8
msstd_fs_chmod(path: *const StrObj, mode: i64, follow: u8) -> u8
msstd_fs_access(path: *const StrObj, mode: i64) -> u8
msstd_fs_chown(path: *const StrObj, uid: i64, gid: i64, follow: u8) -> u8
msstd_fs_truncate(path: *const StrObj, size: i64) -> u8
msstd_fs_set_times( path: *const StrObj, accessed_seconds: i64, accessed_nanos: i64, modified_seconds: i64, modified_nanos: i64, follow: u8, ) -> u8
msstd_fs_file_open( path: *const StrObj, flags: i64, mode: i64, out: *mut *mut FileHandle, ) -> u8
msstd_fs_open_flags(mode: *const StrObj, out: *mut i64) -> u8
msstd_fs_file_read_at( h: *mut FileHandle, offset: i64, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msstd_fs_file_read_file( h: *mut FileHandle, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msstd_fs_file_write_at( h: *mut FileHandle, offset: i64, data: *const VecVal, ) -> u8
msstd_fs_file_read_vectors( h: *mut FileHandle, sizes: *const VecVal, offset: i64, out: *mut VecVal, ) -> u8
msstd_fs_file_write_vectors( h: *mut FileHandle, buffers: *const VecVal, offset: i64, ) -> u8
msstd_fs_file_seek( h: *mut FileHandle, offset: i64, origin: i64, out: *mut i64, ) -> u8
msstd_fs_file_stat(h: *mut FileHandle, out: *mut InfoOut) -> u8
msstd_fs_file_truncate(h: *mut FileHandle, size: i64) -> u8
msstd_fs_file_sync(h: *mut FileHandle) -> u8
msstd_fs_file_data_sync(h: *mut FileHandle) -> u8
msstd_fs_file_chmod(h: *mut FileHandle, mode: i64) -> u8
msstd_fs_file_chown(h: *mut FileHandle, uid: i64, gid: i64) -> u8
msstd_fs_file_set_times( h: *mut FileHandle, accessed_seconds: i64, accessed_nanos: i64, modified_seconds: i64, modified_nanos: i64, ) -> u8
msstd_fs_file_read_lines( h: *mut FileHandle, max_bytes: i64, max_lines: i64, out: *mut VecVal, ) -> u8
msstd_fs_file_path(h: *mut FileHandle) -> *mut StrObj
msstd_fs_directory_open( path: *const StrObj, out: *mut *mut DirHandle, ) -> u8
msstd_fs_directory_read( h: *mut DirHandle, name: *mut *mut StrObj, directory: *mut u8, symlink: *mut u8, ) -> u8
msstd_fs_directory_close(h: *mut DirHandle)
msstd_fs_directory_path(h: *mut DirHandle) -> *mut StrObj
msstd_fs_temporary_open( prefix: *const StrObj, out: *mut *mut TempHandle, ) -> u8
msstd_fs_temporary_path(h: *mut TempHandle) -> *mut StrObj
msstd_fs_temporary_close(h: *mut TempHandle) -> u8
msstd_fs_glob( path: *const StrObj, pattern: *const StrObj, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msstd_fs_copy_tree( source: *const StrObj, destination: *const StrObj, replace: u8, entries: i64, bytes: i64, ) -> u8
msstd_fs_copy( source: *const StrObj, destination: *const StrObj, flags: u32, clone: *const StrObj, entries: i64, bytes: i64, filter: Option<CopyFilter>, env: *mut u8, ) -> u8
msstd_fs_glob_entries( path: *const StrObj, patterns: *const VecVal, exclude: *const VecVal, follow_links: u8, max_entries: i64, max_results: i64, callback: Option<EntryFilter>, env: *mut u8, paths: *mut VecVal, names: *mut VecVal, flags: *mut VecVal, ) -> u8
msstd_fs_constants(names: *mut VecVal, values: *mut VecVal)
msrt_cancel_flag (data)
msrt_cancelled() -> !
msrt_io_flush()
msstd_io_failure_message() -> *mut StrObj
msstd_io_standard(which: i64) -> *mut Host
msstd_io_open(path: *const StrObj, out: *mut *mut Host) -> u8
msstd_io_read( h: *mut Host, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msstd_io_read_line( h: *mut Host, has_max: u8, max: i64, out: *mut *mut StrObj, ) -> u8
msstd_io_write_bytes(h: *mut Host, data: *const VecVal) -> u8
msstd_io_write(h: *mut Host, data: *const StrObj) -> u8
msstd_io_flush(h: *mut Host) -> u8
msstd_io_close(h: *mut Host)
msstd_io_is_closed(h: *const Host) -> u8
msrt_cancel_flag (data)
msrt_cancelled() -> !
msrt_io_flush()
msstd_math_atan2(y: f64, x: f64) -> f64
msstd_math_hypot(left: f64, right: f64) -> f64
msstd_math_pow(base: f64, exponent: f64) -> f64
msstd_math_remainder(left: f64, right: f64) -> f64
msstd_math_abs_int(n: i64) -> i64
msstd_math_sign_int(n: i64) -> i64
msstd_math_is_integer(v: f64) -> u8
msstd_math_is_safe_integer(v: f64) -> u8
msstd_math_abs (unary f64 -> f64)
msstd_math_acos (unary f64 -> f64)
msstd_math_asin (unary f64 -> f64)
msstd_math_atan (unary f64 -> f64)
msstd_math_ceil (unary f64 -> f64)
msstd_math_cos (unary f64 -> f64)
msstd_math_cosh (unary f64 -> f64)
msstd_math_exp (unary f64 -> f64)
msstd_math_floor (unary f64 -> f64)
msstd_math_log (unary f64 -> f64)
msstd_math_log10 (unary f64 -> f64)
msstd_math_log2 (unary f64 -> f64)
msstd_math_round (unary f64 -> f64)
msstd_math_sin (unary f64 -> f64)
msstd_math_sinh (unary f64 -> f64)
msstd_math_sqrt (unary f64 -> f64)
msstd_math_tan (unary f64 -> f64)
msstd_math_tanh (unary f64 -> f64)
msstd_math_truncate (unary f64 -> f64)
msstd_math_acosh (unary f64 -> f64)
msstd_math_asinh (unary f64 -> f64)
msstd_math_atanh (unary f64 -> f64)
msstd_math_cbrt (unary f64 -> f64)
msstd_math_expm1 (unary f64 -> f64)
msstd_math_log1p (unary f64 -> f64)
msstd_math_sign (unary f64 -> f64)
msstd_math_to_float32 (unary f64 -> f64)
msstd_math_e() -> f64
msstd_math_pi() -> f64
msstd_math_infinity() -> f64
msstd_math_nan() -> f64
msstd_math_epsilon() -> f64
msstd_math_max_float() -> f64
msstd_math_min_float() -> f64
msstd_math_max_int() -> i64
msstd_math_min_int() -> i64
msstd_math_max_safe_integer() -> i64
msstd_math_min_safe_integer() -> i64
msstd_math_ln2() -> f64
msstd_math_ln10() -> f64
msstd_math_log2e() -> f64
msstd_math_log10e() -> f64
msstd_math_sqrt2() -> f64
msstd_math_sqrt_half() -> f64
msstd_process_failure_message() -> *mut StrObj
msstd_process_monotonic_time() -> i64
msstd_process_uptime() -> i64
msstd_process_environment(names: *mut VecVal, values: *mut VecVal) -> u8
msstd_process_set_environment( name: *const StrObj, has_value: u8, value: *const StrObj, ) -> u8
msstd_process_load_environment( path: *const StrObj, has_max: u8, max: i64, ) -> u8
msstd_process_working_directory(out: *mut *mut StrObj) -> u8
msstd_process_change_directory(path: *const StrObj) -> u8
msstd_process_send_signal(pid: i64, signal: i64) -> u8
msstd_process_groups(out: *mut VecVal) -> u8
msstd_process_set_groups(groups: *const VecVal) -> u8
msstd_process_initialize_groups(username: *const StrObj, gid: i64) -> u8
msstd_process_umask(mask: i64, out: *mut i64) -> u8
msstd_process_set_identity(kind: *const StrObj, id: i64) -> u8
msstd_process_title(out: *mut *mut StrObj) -> u8
msstd_process_set_title(title: *const StrObj) -> u8
msstd_process_constrained_memory(out: *mut i64) -> u8
msstd_process_available_memory(out: *mut i64) -> u8
msstd_process_resource_usage(out: *mut ResourceOut) -> u8
msstd_process_watch_signals( signals: *const VecVal, has_capacity: u8, capacity: i64, out: *mut *mut SignalHandle, ) -> u8
msstd_process_signal_next(h: *mut SignalHandle, out: *mut i64) -> u8
msstd_process_signal_close(h: *mut SignalHandle)
msstd_process_memory_usage(out: *mut MemoryOut) -> u8
msstd_process_info(out: *mut InfoOut) -> u8
msstd_process_replace( program: *const StrObj, arguments: *const VecVal, env_names: *const VecVal, env_values: *const VecVal, ) -> u8
msstd_process_command_run( program: *const StrObj, arguments: *const VecVal, input: *const VecVal, has_max: u8, max: i64, has_timeout: u8, timeout_ns: i64, out: *mut CommandOut, ) -> u8
msstd_process_command_spawn( program: *const StrObj, arguments: *const VecVal, out: *mut *mut ChildHandle, ) -> u8
msstd_process_subprocess_stream( h: *mut ChildHandle, which: i64, ) -> *mut Handle<Stream>
msstd_process_subprocess_wait( h: *mut ChildHandle, has_timeout: u8, timeout_ns: i64, out: *mut i64, ) -> u8
msstd_process_subprocess_terminate(h: *mut ChildHandle)
msstd_process_subprocess_kill(h: *mut ChildHandle)
msstd_process_subprocess_close(h: *mut ChildHandle)
msrt_cancel_flag (data)
msrt_cancelled() -> !
msrt_io_flush()
msrt_heap_stats(out: *mut i64)
msrt_start_nanos() -> i64
msrt_argv(_: *mut ms_rt_abi::VecVal)
msstd_time_duration_add(left: i64, other: i64) -> i64
msstd_time_duration_plus(left: i64, right: i64) -> i64
msstd_time_duration_minus(left: i64, right: i64) -> i64
msstd_time_duration_subtract(left: i64, other: i64) -> i64
msstd_time_duration_multiply(value: i64, factor: i64) -> i64
msstd_time_duration_divide(value: i64, divisor: i64) -> i64
msstd_time_duration_negate(value: i64) -> i64
msstd_time_duration_abs(value: i64) -> i64
msstd_time_duration_compare(left: i64, other: i64) -> i64
msstd_time_duration_to_microseconds(value: i64) -> i64
msstd_time_duration_to_milliseconds(value: i64) -> i64
msstd_time_duration_to_seconds(value: i64) -> f64
msstd_time_duration_to_minutes(value: i64) -> f64
msstd_time_duration_to_hours(value: i64) -> f64
msstd_time_instant_shift( value: *const Instant, duration: i64, out: *mut Instant, )
msstd_time_instant_unshift( value: *const Instant, duration: i64, out: *mut Instant, )
msstd_time_instant_difference( left: *const Instant, other: *const Instant, ) -> i64
msstd_time_instant_compare( left: *const Instant, other: *const Instant, ) -> i64
msstd_time_instant_equal( left: *const Instant, other: *const Instant, ) -> u8
msstd_time_clock_now(out: *mut Instant)
msstd_time_wall_clock_now(out: *mut Timestamp)
msstd_time_sleep(duration: i64)
msstd_time_timestamp( seconds: i64, nanoseconds: i64, out: *mut Timestamp, ) -> u8
msstd_time_parse_timestamp( text: *const StrObj, out: *mut Timestamp, ) -> u8
msstd_time_timestamp_to_string( value: *const Timestamp, ) -> *mut StrObj
msstd_time_timestamp_shift( value: *const Timestamp, duration: i64, out: *mut Timestamp, ) -> u8
msstd_time_timestamp_difference( left: *const Timestamp, other: *const Timestamp, out: *mut i64, ) -> u8
msstd_time_timestamp_compare( left: *const Timestamp, other: *const Timestamp, ) -> i64
msstd_time_timestamp_calendar( value: *const Timestamp, zone: *const StrObj, out: *mut CalendarOut, ) -> u8
msstd_time_timestamp_format( value: *const Timestamp, pattern: *const StrObj, zone: *const StrObj, out: *mut *mut StrObj, ) -> u8
msstd_time_from_calendar( year: i64, month: i64, day: i64, hour: i64, minute: i64, second: i64, nanosecond: i64, zone: *const StrObj, out: *mut Timestamp, ) -> u8
msstd_time_local_zone() -> *mut StrObj
msstd_time_error_message(status: u8) -> *mut StrObj
```
