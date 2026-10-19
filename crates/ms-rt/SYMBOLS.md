# ms-rt symbol catalogue

Generated from the `#[unsafe(no_mangle)]` items in `crates/ms-rt/src` by `crates/ms-rt/gen-symbols.py`; do not edit.

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
msrt_alloc(size: usize) -> *mut u8
msrt_alloc_zeroed(size: usize) -> *mut u8
msrt_realloc(p: *mut u8, size: usize) -> *mut u8
msrt_free(p: *mut u8)
msrt_retain(o: *mut Obj)
msrt_release(o: *mut Obj)
msrt_drop_slow(o: *mut Obj)
msrt_process_exit(code: i64) -> !
msrt_start( main_fn: extern "C-unwind" fn() -> i64, tables: *const Tables, argc: i32, argv: *const *const u8, ) -> i32
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
```
