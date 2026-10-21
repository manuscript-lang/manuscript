# ms-rt symbol catalogue

Generated from the `#[unsafe(no_mangle)]` items in `crates/ms-rt/src` and `crates/ms-std-*/src` by `crates/ms-rt/gen-symbols.py`; do not edit.

```text
msrt_bits_bit_and(left: i64, right: i64) -> i64
msrt_bits_bit_or(left: i64, right: i64) -> i64
msrt_bits_bit_xor(left: i64, right: i64) -> i64
msrt_bits_bit_not(value: i64) -> i64
msrt_bits_shift_left(value: i64, count: i64) -> i64
msrt_bits_shift_right(value: i64, count: i64) -> i64
msrt_bits_shift_right_unsigned(value: i64, count: i64) -> i64
msrt_bits_rotate_left(value: i64, count: i64) -> i64
msrt_bits_rotate_right(value: i64, count: i64) -> i64
msrt_bits_count_ones(value: i64) -> i64
msrt_bits_leading_zeros(value: i64) -> i64
msrt_bits_trailing_zeros(value: i64) -> i64
msrt_bits_wrapping_add(left: i64, right: i64) -> i64
msrt_bits_wrapping_subtract(left: i64, right: i64) -> i64
msrt_bits_wrapping_multiply(left: i64, right: i64) -> i64
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
msrt_cleanup_discard(handle: usize)
msrt_cancelled() -> !
msrt_guard_call( code: unsafe extern "C-unwind" fn(*mut u8), data: *mut u8, msg_out: *mut *mut ms_rt_abi::StrObj, ) -> u8
msrt_io_write_stdout(s: *mut StrObj)
msrt_io_write_stderr(s: *mut StrObj)
msrt_test_site(message: *mut StrObj, site: *mut StrObj)
msrt_test_site_report(message: *mut StrObj)
msrt_io_write_bytes_stdout(v: *const VecVal)
msrt_io_write_bytes_stderr(v: *const VecVal)
msrt_io_flush()
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
msrt_process_on_exit(hook: extern "C" fn())
msrt_process_exit(code: i64) -> !
msrt_queue_new( d: *const TypeDesc, has_capacity: u8, capacity: i64, ) -> *mut QueueObj
msrt_queue_enqueue(q: *mut QueueObj, value: *mut u8) -> u8
msrt_queue_dequeue(q: *mut QueueObj, out: *mut u8) -> u8
msrt_queue_peek(q: *const QueueObj, out: *mut u8) -> u8
msrt_queue_length(q: *const QueueObj) -> i64
msrt_queue_is_empty(q: *const QueueObj) -> u8
msrt_priority_queue_new( d: *const TypeDesc, compare: *mut Closure, has_capacity: u8, capacity: i64, ) -> *mut PriorityQueueObj
msrt_priority_queue_enqueue( q: *mut PriorityQueueObj, value: *mut u8, ) -> u8
msrt_priority_queue_dequeue( q: *mut PriorityQueueObj, out: *mut u8, ) -> u8
msrt_priority_queue_peek( q: *const PriorityQueueObj, out: *mut u8, ) -> u8
msrt_priority_queue_length(q: *const PriorityQueueObj) -> i64
msrt_priority_queue_is_empty(q: *const PriorityQueueObj) -> u8
msrt_start_nanos() -> i64
msrt_start( main_fn: extern "C-unwind" fn() -> i64, tables: *const Tables, argc: i32, argv: *const *const u8, ) -> i32
msrt_argv(out: *mut VecVal)
msrt_args_consume()
msrt_args(out: *mut VecVal)
msrt_string_empty() -> *mut StrObj
msrt_string_hash(s: *const StrObj) -> i64
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
msrt_strbuf_new() -> *mut StrBuf
msrt_strbuf_push(buf: *mut StrBuf, s: *const StrObj)
msrt_strbuf_finish(buf: *mut StrBuf) -> *mut StrObj
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
msrt_task_spawn( entry: Entry, arg: *mut u8, flags: u32, stack_bytes: usize, ) -> u64
msrt_task_yield()
msrt_task_set_prepark(hook: Option<unsafe extern "C-unwind" fn()>)
msrt_task_wait_fd(fd: i32, events: u32, timeout_ns: i64) -> u32
msrt_task_sleep(ns: i64) -> u32
msrt_task_current() -> u64
msrt_task_count() -> usize
msrt_task_cancel(handle: u64)
msrt_task_join(handle: u64, msg_out: *mut *mut StrObj) -> u8
msrt_trap_begin() -> u8
msrt_trap_end() -> !
msrt_trap_wait(out: *mut *mut StrObj) -> u8
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
msrt_list_insert_copy( v: *mut VecVal, d: *const TypeDesc, index: i64, e: *const u8, )
msrt_list_pop( v: *mut VecVal, d: *const TypeDesc, out: *mut u8, ) -> u8
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
msrt_strbuilder_append_int(b: *mut VecVal, n: i64)
msrt_strbuilder_freeze(b: *mut VecVal) -> *mut StrObj
msrt_strbuilder_drop(b: *mut VecVal)
msrt_hash_list(v: *const VecVal, d: *const TypeDesc) -> i64
msrt_archive_pack( entries: *const VecVal, format: *const StrObj, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msrt_archive_unpack( data: *const VecVal, format: *const StrObj, has_limits: u8, has_entries: u8, max_entries: i64, has_entry_bytes: u8, max_entry_bytes: i64, has_total: u8, max_total_bytes: i64, out: *mut VecVal, ) -> u8
msstd_bigint_from_int(value: i64) -> *mut BigObj
msstd_bigint_from_u64(value: i64) -> *mut BigObj
msstd_bigint_from_seconds_nanos(seconds: i64, nanoseconds: i64) -> *mut BigObj
msstd_bigint_parse( text: *const StrObj, radix: i64, has_max: u8, max: i64, out: *mut *mut BigObj, ) -> u8
msstd_bigint_add(a: *const BigObj, other: *const BigObj) -> *mut BigObj
msstd_bigint_subtract( a: *const BigObj, other: *const BigObj, ) -> *mut BigObj
msstd_bigint_multiply( a: *const BigObj, other: *const BigObj, ) -> *mut BigObj
msstd_bigint_bit_and( a: *const BigObj, other: *const BigObj, ) -> *mut BigObj
msstd_bigint_bit_or( a: *const BigObj, other: *const BigObj, ) -> *mut BigObj
msstd_bigint_bit_xor( a: *const BigObj, other: *const BigObj, ) -> *mut BigObj
msstd_bigint_divide( a: *const BigObj, other: *const BigObj, out: *mut *mut BigObj, ) -> u8
msstd_bigint_remainder( a: *const BigObj, other: *const BigObj, out: *mut *mut BigObj, ) -> u8
msstd_bigint_compare(a: *const BigObj, other: *const BigObj) -> i64
msstd_bigint_bit_not(a: *const BigObj) -> *mut BigObj
msstd_bigint_negate(a: *const BigObj) -> *mut BigObj
msstd_bigint_abs(a: *const BigObj) -> *mut BigObj
msstd_bigint_sign(a: *const BigObj) -> i64
msstd_bigint_pow( a: *const BigObj, exponent: i64, out: *mut *mut BigObj, ) -> u8
msstd_bigint_shift_left( a: *const BigObj, count: i64, out: *mut *mut BigObj, ) -> u8
msstd_bigint_shift_right( a: *const BigObj, count: i64, out: *mut *mut BigObj, ) -> u8
msstd_bigint_to_float(a: *const BigObj) -> f64
msstd_bigint_to_int(a: *const BigObj, out: *mut i64) -> u8
msstd_bigint_to_string_radix(a: *const BigObj, radix: i64) -> *mut StrObj
msstd_bigint_equal(a: *const BigObj, other: *const BigObj) -> u8
msrt_compress_compress( data: *const VecVal, format: *const StrObj, level: i64, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msrt_compress_decompress( data: *const VecVal, format: *const StrObj, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msrt_compress_decoder_new( format: *const StrObj, has_max: u8, max: i64, out: *mut *mut DecoderObj, ) -> u8
msrt_compress_decoder_feed(d: *mut DecoderObj, data: *const VecVal)
msrt_compress_decoder_finish_input(d: *mut DecoderObj)
msrt_compress_decoder_poll( d: *mut DecoderObj, max: i64, out: *mut VecVal, ) -> u8
msrt_compress_encoder_new( format: *const StrObj, level: i64, out: *mut *mut EncoderObj, ) -> u8
msrt_compress_encoder_feed(e: *mut EncoderObj, data: *const VecVal)
msrt_compress_encoder_finish(e: *mut EncoderObj)
msrt_compress_encoder_has_output(e: *const EncoderObj) -> u8
msrt_compress_encoder_is_finished(e: *const EncoderObj) -> u8
msrt_compress_encoder_take( e: *mut EncoderObj, max: i64, out: *mut VecVal, )
msrt_crypto_ecdsa_sign( private_key: *const VecVal, alg: i64, data: *const VecVal, out: *mut VecVal, ) -> u8
msrt_crypto_rsa_sign( private_key: *const VecVal, alg: i64, data: *const VecVal, out: *mut VecVal, ) -> u8
msrt_crypto_rsa_sign_pss( private_key: *const VecVal, alg: i64, data: *const VecVal, out: *mut VecVal, ) -> u8
msrt_crypto_rsa_encrypt( private_key: *const VecVal, alg: i64, data: *const VecVal, out: *mut VecVal, ) -> u8
msrt_crypto_rsa_decrypt( private_key: *const VecVal, alg: i64, data: *const VecVal, out: *mut VecVal, ) -> u8
msrt_crypto_ecdsa_verify( public_key: *const VecVal, alg: i64, data: *const VecVal, signature: *const VecVal, ) -> u8
msrt_crypto_rsa_verify( public_key: *const VecVal, alg: i64, data: *const VecVal, signature: *const VecVal, ) -> u8
msrt_crypto_rsa_verify_pss( public_key: *const VecVal, alg: i64, data: *const VecVal, signature: *const VecVal, ) -> u8
msrt_crypto_digest(alg: i64, data: *const VecVal, out: *mut VecVal)
msrt_crypto_hmac( alg: i64, key: *const VecVal, data: *const VecVal, out: *mut VecVal, ) -> u8
msrt_crypto_derive_key( alg: i64, password: *const VecVal, salt: *const VecVal, iterations: i64, length: i64, out: *mut VecVal, ) -> u8
msrt_crypto_hkdf( alg: i64, secret: *const VecVal, salt: *const VecVal, info: *const VecVal, length: i64, out: *mut VecVal, ) -> u8
msrt_crypto_constant_time_equal( left: *const VecVal, right: *const VecVal, ) -> u8
msrt_crypto_sign( seed: *const VecVal, data: *const VecVal, out: *mut VecVal, ) -> u8
msrt_crypto_public_key(seed: *const VecVal, out: *mut VecVal) -> u8
msrt_crypto_verify( key: *const VecVal, data: *const VecVal, signature: *const VecVal, ) -> u8
msrt_crypto_hasher_new(alg: i64) -> *mut HasherObj
msrt_crypto_hmac_hasher_new( alg: i64, key: *const VecVal, ) -> *mut HasherObj
msrt_crypto_hasher_update(h: *mut HasherObj, data: *const VecVal)
msrt_crypto_hasher_finish(h: *mut HasherObj, out: *mut VecVal)
msrt_crypto_ecdsa_generate(curve: i64, out: *mut VecVal) -> u8
msrt_crypto_public_key_der(key: *const VecVal, out: *mut VecVal) -> u8
msrt_crypto_ecdh_shared_secret( private_key: *const VecVal, peer: *const VecVal, out: *mut VecVal, ) -> u8
msrt_crypto_rsa_generate(bits: i64, out: *mut VecVal) -> u8
msrt_crypto_seal(key: *const VecVal, nonce: *const VecVal, data: *const VecVal, aad: *const VecVal, out: *mut VecVal) -> u8
msrt_crypto_open(key: *const VecVal, nonce: *const VecVal, data: *const VecVal, aad: *const VecVal, out: *mut VecVal) -> u8
msrt_crypto_aes_ctr(key: *const VecVal, iv: *const VecVal, data: *const VecVal, out: *mut VecVal) -> u8
msrt_crypto_aes_cbc_encrypt(key: *const VecVal, iv: *const VecVal, data: *const VecVal, out: *mut VecVal) -> u8
msrt_crypto_aes_cbc_decrypt(key: *const VecVal, iv: *const VecVal, data: *const VecVal, out: *mut VecVal) -> u8
msrt_csv_parse( text: *const StrObj, delimiter: *const StrObj, line_ending: *const StrObj, has_max_rows: u8, max_rows: i64, has_max_cells: u8, max_cells: i64, out: *mut VecVal, ) -> u8
msrt_csv_stringify( rows: *const VecVal, delimiter: *const StrObj, line_ending: *const StrObj, has_max_bytes: u8, max_bytes: i64, out: *mut *mut StrObj, ) -> u8
msstd_decimal_literal(text: *const StrObj, out: *mut Dec)
msstd_decimal_from_int(n: i64, out: *mut Dec)
msstd_decimal_divide(a: *const Dec, b: *const Dec, out: *mut Dec)
msstd_decimal_negate(a: *const Dec, out: *mut Dec)
msstd_decimal_compare(a: *const Dec, b: *const Dec) -> i64
msstd_decimal_to_string(a: *const Dec) -> *mut StrObj
msstd_decimal_to_float(a: *const Dec) -> f64
msstd_decimal_truncate_to_int(a: *const Dec, out: *mut i64) -> u8
msstd_decimal_round( value: *const Dec, places: i64, has_mode: u8, mode: i64, out: *mut Dec, ) -> u8
msstd_decimal_to_fixed( value: *const Dec, digits: i64, has_mode: u8, mode: i64, out: *mut *mut StrObj, ) -> u8
msrt_binary_read_integer( data: *const VecVal, offset: i64, width: i64, signed: u8, little: u8, out: *mut i64, ) -> u8
msrt_binary_read_float( data: *const VecVal, offset: i64, little: u8, out: *mut f64, ) -> u8
msrt_binary_write_integer( value: i64, width: i64, signed: u8, little: u8, out: *mut VecVal, ) -> u8
msrt_binary_write_float(value: f64, little: u8, out: *mut VecVal)
msrt_encoding_hex_encode(data: *const VecVal) -> *mut StrObj
msrt_encoding_hex_decode( text: *const StrObj, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msrt_encoding_base64_encode( data: *const VecVal, url_safe: u8, ) -> *mut StrObj
msrt_encoding_base64_decode( text: *const StrObj, url_safe: u8, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msrt_encoding_utf16_encode( text: *const StrObj, little_endian: u8, out: *mut VecVal, )
msrt_encoding_utf16_decode( data: *const VecVal, little_endian: u8, has_max: u8, max: i64, out: *mut *mut StrObj, ) -> u8
msrt_encoding_latin1_encode(text: *const StrObj, out: *mut VecVal) -> u8
msrt_encoding_latin1_decode(data: *const VecVal) -> *mut StrObj
msrt_encoding_ascii_encode(text: *const StrObj, out: *mut VecVal) -> u8
msrt_encoding_ascii_decode( data: *const VecVal, out: *mut *mut StrObj, ) -> u8
msstd_fs_failure_message() -> *mut StrObj
msstd_fs_read_file( path: *const StrObj, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msstd_fs_write_file( path: *const StrObj, data: *const VecVal, replace: u8, ) -> u8
msstd_fs_append_file(path: *const StrObj, data: *const VecVal) -> u8
msstd_fs_copy_file( source: *const StrObj, destination: *const StrObj, replace: u8, has_max: u8, max: i64, ) -> u8
msstd_fs_stat(path: *const StrObj, follow: u8, out: *mut InfoOut) -> u8
msstd_fs_list( path: *const StrObj, has_limit: u8, limit: i64, out: *mut VecVal, ) -> u8
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
msstd_fs_open( path: *const StrObj, flags: *const StrObj, mode: i64, out: *mut *mut FileHandle, ) -> u8
msstd_fs_file_reader(h: *mut FileHandle) -> *mut Handle<stream::Stream>
msstd_fs_file_writer(h: *mut FileHandle) -> *mut Handle<stream::Stream>
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
msstd_fs_directory_read(h: *mut DirHandle, out: *mut EntryOut) -> u8
msstd_fs_directory_close(h: *mut DirHandle)
msstd_fs_directory_path(h: *mut DirHandle) -> *mut StrObj
msstd_fs_temporary_open( prefix: *const StrObj, out: *mut *mut TempHandle, ) -> u8
msstd_fs_temporary_path(h: *mut TempHandle) -> *mut StrObj
msstd_fs_temporary_close(h: *mut TempHandle) -> u8
msstd_fs_glob( path: *const StrObj, pattern: *const StrObj, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msstd_fs_copy_tree( source: *const StrObj, destination: *const StrObj, replace: u8, entries: i64, bytes: i64, ) -> u8
msstd_fs_copy( source: *const StrObj, destination: *const StrObj, flags: i64, clone: *const StrObj, has_entries: u8, entries: i64, has_bytes: u8, bytes: i64, filter: *mut Closure, ) -> u8
msstd_fs_glob_entries( path: *const StrObj, patterns: *const VecVal, exclude: *const VecVal, follow_links: u8, has_max_entries: u8, max_entries: i64, has_max_results: u8, max_results: i64, filter: *mut Closure, out: *mut VecVal, ) -> u8
msstd_fs_constants(names: *mut VecVal, values: *mut VecVal)
msstd_fs_watch( path: *const StrObj, recursive: u8, interval_ns: i64, has_max: u8, max: i64, out: *mut *mut WatchHandle, ) -> u8
msstd_fs_watch_native( path: *const StrObj, recursive: u8, has_max: u8, max: i64, has_events: u8, events: i64, overflow: *const StrObj, out: *mut *mut WatchHandle, ) -> u8
msstd_fs_watch_next( h: *mut WatchHandle, paths: *mut VecVal, kinds: *mut VecVal, ) -> u8
msstd_fs_watch_close(h: *mut WatchHandle)
msrt_html_escape(text: *const StrObj) -> *mut StrObj
msrt_html_unescape(text: *const StrObj) -> *mut StrObj
msrt_html_parse( text: *const StrObj, has_max_bytes: u8, max_bytes: i64, has_max_depth: u8, max_depth: i64, has_max_nodes: u8, max_nodes: i64, out: *mut *mut TreeObj, root: *mut u32, ) -> u8
msrt_html_kind(t: *const TreeObj, id: u32) -> u8
msrt_html_data(t: *const TreeObj, id: u32) -> *mut StrObj
msrt_html_namespace(t: *const TreeObj, id: u32) -> *mut StrObj
msrt_html_doctype_id( t: *const TreeObj, id: u32, which: u8, ) -> *mut StrObj
msrt_html_child_count(t: *const TreeObj, id: u32) -> i64
msrt_html_child(t: *const TreeObj, id: u32, i: i64) -> u32
msrt_html_first_child(t: *const TreeObj, id: u32) -> u32
msrt_html_next_sibling(t: *const TreeObj, id: u32) -> u32
msrt_html_attr_count(t: *const TreeObj, id: u32) -> i64
msrt_html_attr( t: *const TreeObj, id: u32, i: i64, which: u8, ) -> *mut StrObj
msstd_io_acc_new(kind: i64, has_max: u8, max: i64) -> *mut Acc
msstd_io_acc_want(a: *const Acc) -> i64
msstd_io_acc_push(a: *mut Acc, data: *const VecVal) -> u8
msstd_io_acc_finish_bytes(a: *mut Acc, out: *mut VecVal) -> u8
msstd_io_acc_finish_count(a: *mut Acc, out: *mut i64) -> u8
msstd_io_acc_finish_line(a: *mut Acc, out: *mut *mut StrObj) -> u8
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
msrt_json_parse( text: *const StrObj, has_max_bytes: u8, max_bytes: i64, has_max_depth: u8, max_depth: i64, has_max_values: u8, max_values: i64, out: *mut *mut DocObj, root: *mut u32, ) -> u8
msrt_json_kind(d: *const DocObj, id: u32) -> u8
msrt_json_bool(d: *const DocObj, id: u32) -> u8
msrt_json_text(d: *const DocObj, id: u32) -> *mut StrObj
msrt_json_len(d: *const DocObj, id: u32) -> i64
msrt_json_item(d: *const DocObj, id: u32, i: i64) -> u32
msrt_json_key(d: *const DocObj, id: u32, i: i64) -> *mut StrObj
msrt_json_builder_new() -> *mut DocObj
msrt_json_add_null(d: *mut DocObj) -> u32
msrt_json_add_bool(d: *mut DocObj, v: u8) -> u32
msrt_json_add_number(d: *mut DocObj, text: *const StrObj) -> u32
msrt_json_add_string(d: *mut DocObj, text: *const StrObj) -> u32
msrt_json_add_array(d: *mut DocObj, ids: *const u32, n: i64) -> u32
msrt_json_add_object( d: *mut DocObj, keys: *const *const StrObj, ids: *const u32, n: i64, ) -> u32
msrt_json_stringify( d: *const DocObj, root: u32, has_max_bytes: u8, max_bytes: i64, has_indent: u8, indent: i64, out: *mut *mut StrObj, ) -> u8
msrt_json_dec_int(text: *const StrObj, out: *mut i64) -> u8
msrt_json_dec_float(text: *const StrObj, out: *mut f64) -> u8
msrt_json_add_float(d: *mut DocObj, v: f64) -> u32
msrt_json_add_empty_array(d: *mut DocObj) -> u32
msrt_json_array_push(d: *mut DocObj, arr: u32, item: u32)
msrt_json_add_empty_object(d: *mut DocObj) -> u32
msrt_json_object_put( d: *mut DocObj, obj: u32, key: *const StrObj, item: u32, )
msrt_json_find(d: *const DocObj, id: u32, key: *const StrObj) -> i64
msrt_json_has_unknown( d: *const DocObj, id: u32, names: *const VecVal, ) -> u8
msrt_json_variant( d: *const DocObj, id: u32, names: *const VecVal, payload: *mut i64, ) -> i64
msrt_json_enc_float(v: f64) -> *mut StrObj
msrt_logcore_new_state( has_level: u8, level: i64, has_timestamp: u8, timestamp: u8, has_max: u8, max: i64, out: *mut *mut LoggerObj, ) -> u8
msrt_logcore_child( l: *const LoggerObj, fields: *const StrObj, out: *mut *mut LoggerObj, ) -> u8
msrt_logcore_enabled(l: *const LoggerObj, level: i64) -> u8
msrt_logcore_level(l: *const LoggerObj) -> i64
msrt_logcore_set_level(l: *const LoggerObj, level: i64)
msrt_logcore_line( l: *const LoggerObj, level: i64, message: *const StrObj, now_ms: i64, out: *mut *mut StrObj, ) -> u8
msrt_logcore_line_json( l: *const LoggerObj, level: i64, message: *const StrObj, fields: *const StrObj, now_ms: i64, out: *mut *mut StrObj, ) -> u8
msrt_logcore_new_gate() -> *mut GateObj
msrt_logcore_shut(g: *const GateObj)
msrt_logcore_is_shut(g: *const GateObj) -> u8
msrt_logcore_object_text(text: *const StrObj) -> *mut StrObj
msstd_math_atan2(y: f64, x: f64) -> f64
msstd_math_hypot(left: f64, right: f64) -> f64
msstd_math_pow(base: f64, exponent: f64) -> f64
msstd_math_remainder(left: f64, right: f64) -> f64
msstd_math_abs_int(n: i64) -> i64
msstd_math_sign_int(n: i64) -> i64
msstd_math_is_integer(v: f64) -> u8
msstd_math_is_safe_integer(v: f64) -> u8
msstd_math_abs(value: f64) -> f64
msstd_math_acos(value: f64) -> f64
msstd_math_asin(value: f64) -> f64
msstd_math_atan(value: f64) -> f64
msstd_math_ceil(value: f64) -> f64
msstd_math_cos(value: f64) -> f64
msstd_math_cosh(value: f64) -> f64
msstd_math_exp(value: f64) -> f64
msstd_math_floor(value: f64) -> f64
msstd_math_log(value: f64) -> f64
msstd_math_log10(value: f64) -> f64
msstd_math_log2(value: f64) -> f64
msstd_math_round(value: f64) -> f64
msstd_math_sin(value: f64) -> f64
msstd_math_sinh(value: f64) -> f64
msstd_math_sqrt(value: f64) -> f64
msstd_math_tan(value: f64) -> f64
msstd_math_tanh(value: f64) -> f64
msstd_math_truncate(value: f64) -> f64
msstd_math_acosh(value: f64) -> f64
msstd_math_asinh(value: f64) -> f64
msstd_math_atanh(value: f64) -> f64
msstd_math_cbrt(value: f64) -> f64
msstd_math_expm1(value: f64) -> f64
msstd_math_log1p(value: f64) -> f64
msstd_math_sign(value: f64) -> f64
msstd_math_to_float32(value: f64) -> f64
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
msrt_http_error_message(status: u8, failed: *const StrObj) -> *mut StrObj
msrt_http_headers_new() -> *mut Obj
msrt_http_headers_append( h: *const Obj, name: *const StrObj, value: *const VecVal, ) -> u8
msrt_http_headers_values( h: *const Obj, name: *const StrObj, out: *mut VecVal, ) -> u8
msrt_http_headers_text( h: *const Obj, name: *const StrObj, out: *mut VecVal, ) -> u8
msrt_http_headers_names(h: *const Obj, out: *mut VecVal)
msrt_http_headers_remove(h: *const Obj, name: *const StrObj) -> u8
msrt_http_headers_clone(h: *const Obj) -> *mut Obj
msrt_net_network_http_client( net: *const Obj, opts: *const HttpClientOptionsWire, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_http_client_close(c: *const Obj)
msrt_http_client_request( c: *const Obj, method: *const StrObj, address: *const StrObj, headers: *const Obj, body: *const StrObj, has_max: u8, max: i64, has_timeout: u8, timeout: i64, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_http_client_request_bytes( c: *const Obj, method: *const StrObj, address: *const StrObj, headers: *const Obj, body: *const VecVal, has_max: u8, max: i64, has_timeout: u8, timeout: i64, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_http_client_request_stream( c: *const Obj, method: *const StrObj, address: *const StrObj, headers: *const Obj, src: *mut Obj, has_max: u8, max: i64, has_timeout: u8, timeout: i64, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_http_body_close(b: *const Obj)
msrt_http_body_metadata(b: *const Obj, out: *mut MetadataWire)
msrt_http_body_read( b: *const Obj, has_max: u8, max: i64, out: *mut VecVal, err: *mut *mut StrObj, ) -> u8
msrt_net_network_request( net: *const Obj, method: *const StrObj, address: *const StrObj, headers: *const Obj, body: *const StrObj, has_max: u8, max: i64, has_timeout: u8, timeout: i64, out: *mut ClientResponseWire, err: *mut *mut StrObj, ) -> u8
msrt_net_network_request_bytes( net: *const Obj, method: *const StrObj, address: *const StrObj, headers: *const Obj, body: *const VecVal, has_max: u8, max: i64, has_timeout: u8, timeout: i64, out: *mut ClientResponseWire, err: *mut *mut StrObj, ) -> u8
msrt_net_network_serve( net: *const Obj, address: *const StrObj, env: *mut Obj, has_max_requests: u8, max_requests: i64, has_max_body: u8, max_body: i64, has_max_response: u8, max_response: i64, has_timeout: u8, timeout: i64, has_grace: u8, grace: i64, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_network_serve_stream( net: *const Obj, address: *const StrObj, env: *mut Obj, opts: *const HttpServerOptionsWire, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_http_server_address(s: *const Obj) -> *mut StrObj
msrt_http_server_close(s: *const Obj)
msrt_http_server_wait(s: *const Obj) -> u8
msrt_http_exchange_close(x: *const Obj)
msrt_http_exchange_headers(x: *const Obj) -> *mut Obj
msrt_http_exchange_method(x: *const Obj) -> *mut StrObj
msrt_http_exchange_path(x: *const Obj) -> *mut StrObj
msrt_http_exchange_protocol(x: *const Obj) -> *mut StrObj
msrt_http_exchange_query(x: *const Obj) -> *mut StrObj
msrt_http_exchange_read( x: *const Obj, has_max: u8, max: i64, out: *mut VecVal, err: *mut *mut StrObj, ) -> u8
msrt_http_exchange_send_headers( x: *const Obj, status: i64, headers: *const Obj, err: *mut *mut StrObj, ) -> u8
msrt_http_exchange_write( x: *const Obj, data: *const StrObj, err: *mut *mut StrObj, ) -> u8
msrt_http_exchange_write_bytes( x: *const Obj, data: *const VecVal, err: *mut *mut StrObj, ) -> u8
msrt_net_parse_ip( text: *const StrObj, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_parse_cidr( text: *const StrObj, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_contains_ip( cidr: *const Obj, ip: *const Obj, out: *mut u8, ) -> u8
msrt_net_ip_address_text(ip: *const Obj) -> *mut StrObj
msrt_net_ip_address_family(ip: *const Obj) -> u8
msrt_net_cidr_text(cidr: *const Obj) -> *mut StrObj
msrt_net_ip_family_text(family: u8) -> *mut StrObj
msrt_net_dns_kind_text(kind: u8) -> *mut StrObj
msrt_net_error_message(status: u8, failed: *const StrObj) -> *mut StrObj
msrt_net_network() -> *mut Obj
msrt_net_network_close(net: *const Obj)
msrt_net_network_connect( net: *const Obj, address: *const StrObj, has_timeout: u8, timeout: i64, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_network_connect_unix( net: *const Obj, path: *const StrObj, has_timeout: u8, timeout: i64, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_network_listen( net: *const Obj, address: *const StrObj, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_network_listen_unix( net: *const Obj, path: *const StrObj, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_network_bind_datagram( net: *const Obj, address: *const StrObj, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_network_restrict( net: *const Obj, hosts: *const VecVal, cidrs: *const VecVal, allow_listen: u8, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_network_with_resolver( net: *const Obj, address: *const StrObj, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_network_lookup( net: *const Obj, name: *const StrObj, has_max: u8, max: i64, has_timeout: u8, timeout: i64, out: *mut VecVal, err: *mut *mut StrObj, ) -> u8
msrt_net_network_resolve( net: *const Obj, name: *const StrObj, kind: u8, has_max: u8, max: i64, has_timeout: u8, timeout: i64, records: *mut *mut DnsRecordWire, count: *mut usize, err: *mut *mut StrObj, ) -> u8
msrt_net_connection_close(c: *const Obj)
msrt_net_connection_local_address(c: *const Obj) -> *mut StrObj
msrt_net_connection_peer_address(c: *const Obj) -> *mut StrObj
msrt_net_connection_read( c: *const Obj, has_max: u8, max: i64, has_timeout: u8, timeout: i64, out: *mut VecVal, err: *mut *mut StrObj, ) -> u8
msrt_net_connection_write( c: *const Obj, data: *const StrObj, has_timeout: u8, timeout: i64, err: *mut *mut StrObj, ) -> u8
msrt_net_connection_write_bytes( c: *const Obj, data: *const VecVal, has_timeout: u8, timeout: i64, err: *mut *mut StrObj, ) -> u8
msrt_net_connection_shutdown_write( c: *const Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_listener_accept( l: *const Obj, has_timeout: u8, timeout: i64, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_listener_address(l: *const Obj) -> *mut StrObj
msrt_net_listener_close(l: *const Obj)
msrt_net_datagram_address(sock: *const Obj) -> *mut StrObj
msrt_net_datagram_close(sock: *const Obj)
msrt_net_datagram_receive( sock: *const Obj, has_max: u8, max: i64, has_timeout: u8, timeout: i64, out: *mut DatagramWire, err: *mut *mut StrObj, ) -> u8
msrt_net_datagram_send( sock: *const Obj, data: *const StrObj, address: *const StrObj, has_timeout: u8, timeout: i64, err: *mut *mut StrObj, ) -> u8
msrt_net_datagram_send_bytes( sock: *const Obj, data: *const VecVal, address: *const StrObj, has_timeout: u8, timeout: i64, err: *mut *mut StrObj, ) -> u8
msrt_net_network_connect_tls( net: *const Obj, address: *const StrObj, server_name: *const StrObj, has_timeout: u8, timeout: i64, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_network_connect_tls_config( net: *const Obj, address: *const StrObj, opts: *const TlsOptionsWire, has_timeout: u8, timeout: i64, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_network_listen_tls( net: *const Obj, address: *const StrObj, opts: *const TlsOptionsWire, has_timeout: u8, timeout: i64, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_net_connection_tls_info(c: *const Obj, out: *mut TlsInfoWire) -> u8
msrt_tls_parse_certificates( pem: *const StrObj, has_max: u8, max: i64, certs: *mut *mut CertificateInfoWire, count: *mut usize, ) -> u8
msrt_tls_verify_certificates( chain: *const StrObj, roots: *const StrObj, server_name: *const StrObj, now_seconds: i64, _now_nanos: i32, ) -> u8
msrt_tls_error_message(status: u8) -> *mut StrObj
msrt_websocket_error_message( status: u8, failed: *const StrObj, ) -> *mut StrObj
msrt_net_network_web_socket( net: *const Obj, address: *const StrObj, headers: *const Obj, subprotocols: *const VecVal, opts: *const WebSocketOptionsWire, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_http_exchange_upgrade( x: *const Obj, origins: *const VecVal, subprotocols: *const VecVal, has_max: u8, max: i64, out: *mut *mut Obj, err: *mut *mut StrObj, ) -> u8
msrt_websocket_close(s: *const Obj)
msrt_websocket_subprotocol(s: *const Obj) -> *mut StrObj
msrt_websocket_ping( s: *const Obj, data: *const StrObj, err: *mut *mut StrObj, ) -> u8
msrt_websocket_ping_bytes( s: *const Obj, data: *const VecVal, err: *mut *mut StrObj, ) -> u8
msrt_websocket_send( s: *const Obj, data: *const StrObj, err: *mut *mut StrObj, ) -> u8
msrt_websocket_send_bytes( s: *const Obj, data: *const VecVal, text: u8, err: *mut *mut StrObj, ) -> u8
msrt_websocket_receive( s: *const Obj, data: *mut VecVal, text: *mut u8, present: *mut u8, err: *mut *mut StrObj, ) -> u8
msrt_path_basename(windows: u8, path: *const StrObj) -> *mut StrObj
msrt_path_basename_without( windows: u8, path: *const StrObj, suffix: *const StrObj, ) -> *mut StrObj
msrt_path_dirname(windows: u8, path: *const StrObj) -> *mut StrObj
msrt_path_extension(windows: u8, path: *const StrObj) -> *mut StrObj
msrt_path_is_absolute(windows: u8, path: *const StrObj) -> u8
msrt_path_join(windows: u8, parts: *const VecVal) -> *mut StrObj
msrt_path_normalize(windows: u8, path: *const StrObj) -> *mut StrObj
msrt_path_relative( windows: u8, base: *const StrObj, target: *const StrObj, out: *mut *mut StrObj, ) -> u8
msrt_path_resolve( windows: u8, base: *const StrObj, parts: *const VecVal, out: *mut *mut StrObj, ) -> u8
msrt_path_parse(windows: u8, path: *const StrObj, out: *mut PartsRec)
msrt_path_format(windows: u8, parts: *const PartsRec) -> *mut StrObj
msrt_path_separator(windows: u8) -> *mut StrObj
msrt_path_delimiter(windows: u8) -> *mut StrObj
msrt_path_to_namespaced_path( windows: u8, path: *const StrObj, ) -> *mut StrObj
msrt_path_matches_glob( windows: u8, value: *const StrObj, pattern: *const StrObj, out: *mut u8, ) -> u8
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
msstd_process_elapsed(out: *mut i64) -> u8
msstd_process_environment_map(out: *mut ms_rt_abi::MapVal) -> u8
msstd_process_info_pid() -> i64
msstd_process_info_parent_pid() -> i64
msstd_process_info_executable() -> *mut StrObj
msstd_process_info_arguments(out: *mut VecVal)
msstd_process_info_os() -> *mut StrObj
msstd_process_info_architecture() -> *mut StrObj
msstd_process_info_uid() -> i64
msstd_process_info_gid() -> i64
msstd_process_info_effective_uid() -> i64
msstd_process_info_effective_gid() -> i64
msrt_argv(_: *mut ms_rt_abi::VecVal)
msstd_random_failure_message() -> *mut StrObj
msstd_random_os_bytes(count: i64, out: *mut VecVal) -> u8
msstd_random_draw_new(kind: i64, a: i64, has_b: u8, b: i64) -> *mut Draw
msstd_random_draw_want(d: *const Draw) -> i64
msstd_random_draw_push(d: *mut Draw, data: *const VecVal) -> u8
msstd_random_draw_swap(d: *const Draw, which: i64) -> i64
msstd_random_draw_status(d: *const Draw) -> u8
msstd_random_draw_int(d: *const Draw) -> i64
msstd_random_draw_float(d: *const Draw) -> f64
msstd_random_draw_text(d: *const Draw) -> *mut StrObj
msstd_random_draw_free(d: *mut Draw)
msrt_regex_compile(pattern: *const StrObj, out: *mut *mut RegexObj) -> u8
msrt_regex_matches(re: *const RegexObj, text: *const StrObj) -> u8
msrt_regex_find_all( re: *const RegexObj, text: *const StrObj, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msrt_regex_replace_all( re: *const RegexObj, text: *const StrObj, replacement: *const StrObj, has_max: u8, max: i64, out: *mut *mut StrObj, ) -> u8
msrt_semver_parse(text: *const StrObj, out: *mut VersionRec) -> u8
msrt_semver_format(v: *const VersionRec) -> *mut StrObj
msrt_semver_compare(l: *const VersionRec, r: *const VersionRec) -> i64
msstd_system_failure_message() -> *mut StrObj
msstd_system_endianness() -> *mut StrObj
msstd_system_end_of_line() -> *mut StrObj
msstd_system_dev_null() -> *mut StrObj
msstd_system_os_type() -> *mut StrObj
msstd_system_info_os() -> *mut StrObj
msstd_system_info_architecture() -> *mut StrObj
msstd_system_info_cpu_count() -> i64
msstd_system_working_directory() -> *mut StrObj
msstd_system_hostname(out: *mut *mut StrObj) -> u8
msstd_system_home_directory(out: *mut *mut StrObj) -> u8
msstd_system_os_release(out: *mut *mut StrObj) -> u8
msstd_system_os_version(out: *mut *mut StrObj) -> u8
msstd_system_machine(out: *mut *mut StrObj) -> u8
msstd_system_get_priority(pid: i64, out: *mut i64) -> u8
msstd_system_set_priority(pid: i64, priority: i64) -> u8
msstd_system_constants(out: *mut MapVal)
msstd_system_user_info_status() -> u8
msstd_system_user_info_username() -> *mut StrObj
msstd_system_user_info_uid() -> i64
msstd_system_user_info_gid() -> i64
msstd_system_user_info_home() -> *mut StrObj
msstd_system_user_info_shell() -> *mut StrObj
msstd_system_network_interfaces_status() -> u8
msstd_system_network_interfaces_count() -> i64
msstd_system_network_interfaces_family(i: i64) -> i64
msstd_system_network_interfaces_internal(i: i64) -> u8
msstd_system_cpus_status() -> u8
msstd_system_cpus_count() -> i64
msstd_system_metrics_status() -> u8
msstd_system_metrics_total_memory() -> i64
msstd_system_metrics_free_memory() -> i64
msstd_system_metrics_available_memory() -> i64
msstd_system_metrics_uptime() -> i64
msstd_system_metrics_available_parallelism() -> i64
msstd_system_metrics_load_average(window: i64) -> f64
msstd_system_network_interfaces_name(i: i64) -> *mut StrObj
msstd_system_network_interfaces_address(i: i64) -> *mut StrObj
msstd_system_network_interfaces_netmask(i: i64) -> *mut StrObj
msstd_system_network_interfaces_mac(i: i64) -> *mut StrObj
msstd_system_network_interfaces_scope_id(i: i64) -> i64
msstd_system_cpus_model(i: i64) -> *mut StrObj
msstd_system_cpus_speed_mhz(i: i64) -> i64
msstd_system_cpus_user(i: i64) -> i64
msstd_system_cpus_nice(i: i64) -> i64
msstd_system_cpus_system(i: i64) -> i64
msstd_system_cpus_idle(i: i64) -> i64
msstd_system_cpus_irq(i: i64) -> i64
msstd_terminal_failure_message() -> *mut StrObj
msstd_terminal_capabilities_input_is_terminal() -> u8
msstd_terminal_capabilities_output_is_terminal() -> u8
msstd_terminal_capabilities_error_is_terminal() -> u8
msstd_terminal_capabilities_raw_mode() -> u8
msstd_terminal_capabilities_resize_events() -> u8
msstd_terminal_capabilities_colors() -> i64
msstd_terminal_size_status() -> u8
msstd_terminal_size_columns() -> i64
msstd_terminal_size_rows() -> i64
msstd_terminal_raw_mode( alternate_screen: u8, out: *mut *mut RawHandle, ) -> u8
msstd_terminal_raw_terminal_close(h: *mut RawHandle)
msstd_terminal_raw_terminal_size_status(h: *mut RawHandle) -> u8
msstd_terminal_raw_terminal_size_columns(h: *mut RawHandle) -> i64
msstd_terminal_raw_terminal_size_rows(h: *mut RawHandle) -> i64
msstd_terminal_raw_terminal_move_cursor( h: *mut RawHandle, row: i64, column: i64, ) -> u8
msstd_terminal_raw_terminal_show_cursor( h: *mut RawHandle, visible: u8, ) -> u8
msstd_terminal_raw_terminal_erase(h: *mut RawHandle, region: i64) -> u8
msstd_terminal_raw_terminal_next_event( h: *mut RawHandle, has_timeout: u8, timeout_ns: i64, ) -> u8
msstd_terminal_event_kind() -> i64
msstd_terminal_event_text() -> *mut StrObj
msstd_terminal_event_ctrl() -> u8
msstd_terminal_event_alt() -> u8
msstd_terminal_event_shift() -> u8
msstd_terminal_event_columns() -> i64
msstd_terminal_event_rows() -> i64
msstd_time_duration_add(left: i64, other: i64) -> i64
msstd_time_duration_plus(left: i64, right: i64) -> i64
msstd_time_duration_minus(left: i64, right: i64) -> i64
msstd_time_duration_subtract(left: i64, other: i64) -> i64
msstd_time_int_milliseconds(n: i64) -> i64
msstd_time_int_seconds(n: i64) -> i64
msstd_time_int_minutes(n: i64) -> i64
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
msrt_url_encode_component(text: *const StrObj) -> *mut StrObj
msrt_url_decode_component( text: *const StrObj, out: *mut *mut StrObj, ) -> u8
msrt_url_parse(text: *const StrObj, out: *mut UrlRec) -> u8
msrt_url_resolve( base: *const UrlRec, reference: *const StrObj, out: *mut UrlRec, ) -> u8
msrt_url_format(value: *const UrlRec, out: *mut *mut StrObj) -> u8
msrt_url_parse_query( text: *const StrObj, has_max: u8, max: i64, out: *mut VecVal, ) -> u8
msrt_url_format_query(entries: *const VecVal) -> *mut StrObj
```
