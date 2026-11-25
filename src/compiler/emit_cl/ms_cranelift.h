/* Manuscript's Cranelift library: build functions and data, get one relocatable object.
 *
 * A module (ms_cl) holds declarations and data and writes the object; function builders (ms_cl_fn) build and compile
 * functions, in parallel if you like. Handles (values, blocks, stack slots, signatures, functions, data) are distinct struct types, so mixing them up
 * is a compile error. Values, blocks and slots belong to the function being built (between ms_cl_fn_begin and
 * ms_cl_fn_end); signatures, functions and data belong to the module. A bad handle aborts the process (the caller is
 * a compiler); a failure that depends on the input returns nonzero or null and sets ms_cl_error.
 *
 * Two ways to use it, with identical code:
 *   - Link against the library: include this header.
 *   - Load it at run time: define MS_CL_DYNAMIC, include this header in every file, define MS_CL_DEFINE_API in exactly
 *     one of them, and call ms_cl_bind(resolver, data) once. The resolver maps a symbol name to its address
 *     (dlsym or GetProcAddress on the library handle); ms_cl_bind returns the first missing name, or NULL.
 *
 * Sketch (a function i64 add(i64, i64)):
 *   ms_cl *c = ms_cl_new(NULL, 0, NULL, NULL);
 *   ms_cl_sig s = ms_cl_sig_new(c);
 *   ms_cl_sig_param(c, s, MS_CL_I64, MS_CL_EXT_NONE); ms_cl_sig_param(c, s, MS_CL_I64, MS_CL_EXT_NONE);
 *   ms_cl_sig_ret(c, s, MS_CL_I64, MS_CL_EXT_NONE);
 *   ms_cl_func f = ms_cl_declare_func(c, "add", s, MS_CL_EXPORT);
 *   ms_cl_fn *b = ms_cl_fn_new(c);                 // one builder per thread that builds
 *   ms_cl_fn_begin(b, f);
 *   ms_cl_block blk = ms_cl_entry(b);
 *   ms_cl_ret1(b, ms_cl_iadd(b, ms_cl_block_param(b, blk, 0), ms_cl_block_param(b, blk, 1)));
 *   ms_cl_seal_all(b);
 *   ms_cl_fn_end(b);   // queued for the worker threads; ms_cl_finish waits
 *   size_t n; const uint8_t *object = ms_cl_finish(c, &n);   // valid until ms_cl_free
 */
#ifndef MS_CRANELIFT_H
#define MS_CRANELIFT_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct ms_cl ms_cl;       /* a module */
typedef struct ms_cl_fn ms_cl_fn; /* a function builder */
typedef struct { uint32_t id; } ms_cl_val;
typedef struct { uint32_t id; } ms_cl_block;
typedef struct { uint32_t id; } ms_cl_slot;
typedef struct { uint32_t id; } ms_cl_sig;
typedef struct { uint32_t id; } ms_cl_func;
typedef struct { uint32_t id; } ms_cl_data;
/* A checked operation's result and its overflow flag (an i8). */
typedef struct { ms_cl_val result, flag; } ms_cl_ovf_result;

typedef enum { MS_CL_I8, MS_CL_I16, MS_CL_I32, MS_CL_I64, MS_CL_F32, MS_CL_F64 } ms_cl_type;
/* How a signature extends a narrow argument or result to a full register. */
typedef enum { MS_CL_EXT_NONE, MS_CL_EXT_U, MS_CL_EXT_S } ms_cl_ext;
typedef enum { MS_CL_IMPORT, MS_CL_EXPORT, MS_CL_LOCAL, MS_CL_PREEMPTIBLE } ms_cl_linkage;
/* Memory flags, or-ed. MS_CL_TRUSTED is what Manuscript uses for its own memory: it cannot trap and is aligned. */
typedef enum { MS_CL_NOTRAP = 1, MS_CL_ALIGNED = 2, MS_CL_READONLY = 4, MS_CL_CAN_MOVE = 8,
               MS_CL_TRUSTED = 3 } ms_cl_mem;

typedef enum { MS_CL_INEG, MS_CL_BNOT, MS_CL_CLZ, MS_CL_CTZ, MS_CL_POPCNT, MS_CL_BSWAP, MS_CL_BITREV, MS_CL_IABS,
               MS_CL_FNEG, MS_CL_FABS, MS_CL_SQRT, MS_CL_CEIL, MS_CL_FLOOR, MS_CL_TRUNC, MS_CL_NEAREST } ms_cl_unop;
typedef enum { MS_CL_IADD, MS_CL_ISUB, MS_CL_IMUL, MS_CL_SDIV, MS_CL_UDIV, MS_CL_SREM, MS_CL_UREM, MS_CL_BAND,
               MS_CL_BOR, MS_CL_BXOR, MS_CL_ISHL, MS_CL_SSHR, MS_CL_USHR, MS_CL_ROTL, MS_CL_ROTR, MS_CL_UMULHI,
               MS_CL_SMULHI, MS_CL_FADD, MS_CL_FSUB, MS_CL_FMUL, MS_CL_FDIV, MS_CL_FMIN, MS_CL_FMAX,
               MS_CL_FCOPYSIGN, MS_CL_SMIN, MS_CL_SMAX, MS_CL_UMIN, MS_CL_UMAX, MS_CL_BAND_NOT, MS_CL_BOR_NOT,
               MS_CL_BXOR_NOT } ms_cl_binop;
typedef enum { MS_CL_SADD_OVF, MS_CL_UADD_OVF, MS_CL_SSUB_OVF, MS_CL_USUB_OVF, MS_CL_SMUL_OVF,
               MS_CL_UMUL_OVF } ms_cl_ovfop;
typedef enum { MS_CL_UEXTEND, MS_CL_SEXTEND, MS_CL_IREDUCE, MS_CL_FPROMOTE, MS_CL_FDEMOTE, MS_CL_FCVT_FROM_SINT,
               MS_CL_FCVT_FROM_UINT, MS_CL_FCVT_TO_SINT, MS_CL_FCVT_TO_UINT, MS_CL_FCVT_TO_SINT_SAT,
               MS_CL_FCVT_TO_UINT_SAT, MS_CL_BITCAST } ms_cl_castop;
typedef enum { MS_CL_EQ, MS_CL_NE, MS_CL_SLT, MS_CL_SGE, MS_CL_SGT, MS_CL_SLE, MS_CL_ULT, MS_CL_UGE, MS_CL_UGT,
               MS_CL_ULE } ms_cl_icmp_cc;
typedef enum { MS_CL_FEQ, MS_CL_FNE, MS_CL_FLT, MS_CL_FLE, MS_CL_FGT, MS_CL_FGE, MS_CL_FORD, MS_CL_FUNO,
               MS_CL_FUEQ, MS_CL_FONE, MS_CL_FULT, MS_CL_FULE, MS_CL_FUGT, MS_CL_FUGE } ms_cl_fcmp_cc;
typedef enum { MS_CL_RMW_ADD, MS_CL_RMW_SUB, MS_CL_RMW_AND, MS_CL_RMW_NAND, MS_CL_RMW_OR, MS_CL_RMW_XOR,
               MS_CL_RMW_XCHG, MS_CL_RMW_UMIN, MS_CL_RMW_UMAX, MS_CL_RMW_SMIN, MS_CL_RMW_SMAX } ms_cl_rmwop;

/* A machine-code range of a function, as offsets from its start, with the place given to ms_cl_srcloc (file is
 * UINT32_MAX for code that had none). */
typedef struct { uint32_t off, end, file, line, scope; } ms_cl_code_range;
/* Store the address of a function (kind 0) or data object (kind 1) plus addend at offset. */
typedef struct { uint32_t offset, kind, target; int64_t addend; } ms_cl_reloc;

/* Every function of the library: X(result, name, (parameters)). */
#define MS_CL_API(X) \
  /* Module. triple NULL is the host; keys[i]/vals[i] set Cranelift options (opt_level, regalloc_algorithm, ...). \
     Returns NULL on failure with the message in ms_cl_error(NULL). */ \
  X(ms_cl *, ms_cl_new, (const char *triple, uint32_t n, const char *const *keys, const char *const *vals)) \
  X(const char *, ms_cl_error, (ms_cl *c)) \
  X(void, ms_cl_free, (ms_cl *c)) \
  X(ms_cl_sig, ms_cl_sig_new, (ms_cl *c)) \
  X(void, ms_cl_sig_param, (ms_cl *c, ms_cl_sig s, ms_cl_type t, ms_cl_ext ext)) \
  X(void, ms_cl_sig_ret, (ms_cl *c, ms_cl_sig s, ms_cl_type t, ms_cl_ext ext)) \
  X(ms_cl_func, ms_cl_declare_func, (ms_cl *c, const char *name, ms_cl_sig s, ms_cl_linkage link)) \
  X(ms_cl_data, ms_cl_declare_data, (ms_cl *c, const char *name, ms_cl_linkage link, int writable, int tls)) \
  /* bytes NULL defines zeros. */ \
  X(void, ms_cl_define_data, (ms_cl *c, ms_cl_data d, const uint8_t *bytes, uint32_t len, uint32_t align, \
                              const ms_cl_reloc *relocs, uint32_t nrelocs)) \
  /* Bodies. ms_cl_entry creates and enters the entry block, whose parameters are the function's. */ \
  X(ms_cl_block, ms_cl_block_new, (ms_cl_fn *f)) \
  X(ms_cl_val, ms_cl_block_param_add, (ms_cl_fn *f, ms_cl_block b, ms_cl_type t)) \
  X(ms_cl_val, ms_cl_block_param, (ms_cl_fn *f, ms_cl_block b, uint32_t i)) \
  X(ms_cl_block, ms_cl_entry, (ms_cl_fn *f)) \
  X(void, ms_cl_enter, (ms_cl_fn *f, ms_cl_block b)) \
  X(void, ms_cl_seal, (ms_cl_fn *f, ms_cl_block b)) \
  X(void, ms_cl_seal_all, (ms_cl_fn *f)) \
  X(void, ms_cl_cold, (ms_cl_fn *f, ms_cl_block b)) \
  /* The source place of the instructions that follow: module file index, line, and scope (a DWARF row's column). */ \
  X(void, ms_cl_srcloc, (ms_cl_fn *f, uint32_t file, uint32_t line, uint32_t scope)) \
  X(ms_cl_slot, ms_cl_stack_slot, (ms_cl_fn *f, uint32_t size, uint8_t align_shift)) \
  X(ms_cl_val, ms_cl_stack_addr, (ms_cl_fn *f, ms_cl_slot s, int32_t off)) \
  X(ms_cl_val, ms_cl_sp, (ms_cl_fn *f)) \
  X(ms_cl_val, ms_cl_iconst, (ms_cl_fn *f, ms_cl_type t, int64_t k)) \
  X(ms_cl_val, ms_cl_f32const, (ms_cl_fn *f, float k)) \
  X(ms_cl_val, ms_cl_f64const, (ms_cl_fn *f, double k)) \
  X(ms_cl_val, ms_cl_unary, (ms_cl_fn *f, ms_cl_unop op, ms_cl_val x)) \
  X(ms_cl_val, ms_cl_binary, (ms_cl_fn *f, ms_cl_binop op, ms_cl_val x, ms_cl_val y)) \
  X(ms_cl_ovf_result, ms_cl_ovf, (ms_cl_fn *f, ms_cl_ovfop op, ms_cl_val x, ms_cl_val y)) \
  X(ms_cl_val, ms_cl_cast, (ms_cl_fn *f, ms_cl_castop op, ms_cl_type t, ms_cl_val x)) \
  X(ms_cl_val, ms_cl_icmp, (ms_cl_fn *f, ms_cl_icmp_cc cc, ms_cl_val x, ms_cl_val y)) \
  X(ms_cl_val, ms_cl_fcmp, (ms_cl_fn *f, ms_cl_fcmp_cc cc, ms_cl_val x, ms_cl_val y)) \
  X(ms_cl_val, ms_cl_select, (ms_cl_fn *f, ms_cl_val cond, ms_cl_val a, ms_cl_val b)) \
  X(ms_cl_val, ms_cl_load, (ms_cl_fn *f, ms_cl_type t, uint32_t mem, ms_cl_val base, int32_t off)) \
  /* A load of 8, 16 or 32 bits widened to t. */ \
  X(ms_cl_val, ms_cl_load_ext, (ms_cl_fn *f, uint32_t bits, int is_signed, ms_cl_type t, uint32_t mem, \
                                ms_cl_val base, int32_t off)) \
  X(void, ms_cl_store, (ms_cl_fn *f, uint32_t mem, ms_cl_val v, ms_cl_val base, int32_t off)) \
  /* A store of the low 8, 16 or 32 bits of an integer. */ \
  X(void, ms_cl_store_trunc, (ms_cl_fn *f, uint32_t bits, uint32_t mem, ms_cl_val v, ms_cl_val base, int32_t off)) \
  /* Bulk memory. ms_cl_copy: a constant size, the ranges must not overlap; small sizes are loads and stores, larger \
     ones a call of memcpy. ms_cl_copy_dyn: a size in a value, memmove. ms_cl_fill: a constant size set to a byte. */ \
  X(void, ms_cl_copy, (ms_cl_fn *f, ms_cl_val dst, ms_cl_val src, uint32_t bytes)) \
  X(void, ms_cl_copy_dyn, (ms_cl_fn *f, ms_cl_val dst, ms_cl_val src, ms_cl_val n)) \
  X(void, ms_cl_fill, (ms_cl_fn *f, ms_cl_val dst, uint8_t byte, uint32_t bytes)) \
  X(ms_cl_val, ms_cl_atomic_load, (ms_cl_fn *f, ms_cl_type t, uint32_t mem, ms_cl_val addr)) \
  X(void, ms_cl_atomic_store, (ms_cl_fn *f, uint32_t mem, ms_cl_val v, ms_cl_val addr)) \
  /* Both return the old value. */ \
  X(ms_cl_val, ms_cl_atomic_rmw, (ms_cl_fn *f, ms_cl_rmwop op, ms_cl_type t, uint32_t mem, ms_cl_val addr, ms_cl_val x)) \
  X(ms_cl_val, ms_cl_atomic_cas, (ms_cl_fn *f, uint32_t mem, ms_cl_val addr, ms_cl_val expected, ms_cl_val repl)) \
  X(void, ms_cl_fence, (ms_cl_fn *f)) \
  X(ms_cl_val, ms_cl_func_addr, (ms_cl_fn *f, ms_cl_func func)) \
  X(ms_cl_val, ms_cl_data_addr, (ms_cl_fn *f, ms_cl_data d)) \
  X(void, ms_cl_jump, (ms_cl_fn *f, ms_cl_block to, const ms_cl_val *args, uint32_t n)) \
  X(void, ms_cl_brif, (ms_cl_fn *f, ms_cl_val cond, ms_cl_block then, const ms_cl_val *then_args, uint32_t then_n, \
                       ms_cl_block els, const ms_cl_val *else_args, uint32_t else_n)) \
  /* Multi-way branch on an integer; targets take no block arguments (go through a trampoline block). */ \
  X(void, ms_cl_switch, (ms_cl_fn *f, ms_cl_val v, ms_cl_block dflt, const uint64_t *keys, const ms_cl_block *targets, \
                         uint32_t n)) \
  X(void, ms_cl_ret, (ms_cl_fn *f, const ms_cl_val *vals, uint32_t n)) \
  /* A trap with a user code in 1..250. */ \
  X(void, ms_cl_trap, (ms_cl_fn *f, uint8_t code)) \
  /* rets receives one value per result of the callee's signature (may be NULL when there are none). */ \
  X(void, ms_cl_call, (ms_cl_fn *f, ms_cl_func func, const ms_cl_val *args, uint32_t n, ms_cl_val *rets)) \
  X(void, ms_cl_call_indirect, (ms_cl_fn *f, ms_cl_sig s, ms_cl_val callee, const ms_cl_val *args, uint32_t n, \
                                ms_cl_val *rets)) \
  /* The Cranelift IR of the current function, valid until the next call on c. */ \
  X(const char *, ms_cl_dump, (ms_cl_fn *f)) \
  /* The object file, valid until ms_cl_free; the module takes no input afterwards. NULL on failure. */ \
  X(const uint8_t *, ms_cl_finish, (ms_cl *c, size_t *len)) \
  /* After ms_cl_finish: where the function sits in the object's text section, and its size. */ \
  X(void, ms_cl_func_info, (ms_cl *c, ms_cl_func f, uint64_t *text_offset, uint32_t *size)) \
  X(const ms_cl_code_range *, ms_cl_func_ranges, (ms_cl *c, ms_cl_func f, uint32_t *n)) \
  /* Debug info: the object gets a DWARF line table when at least one file is named (index = module file number, path as a
     debugger should show it). The name of a function is what a debugger shows. */ \
  X(void, ms_cl_dwarf_file, (ms_cl *c, uint32_t index, const char *path)) \
  X(void, ms_cl_dwarf_dir, (ms_cl *c, const char *dir)) \
  X(void, ms_cl_func_name, (ms_cl *c, ms_cl_func f, const char *name)) \
  /* Function builders: one per thread that builds. Declare every signature, function and data object before a body
     mentions it. ms_cl_fn_end hands the function to the module's worker threads (ms_cl_new key "ms_threads", default one
     per core; 1 compiles on the calling thread) and returns at once, so the builder may begin its next function. */ \
  X(ms_cl_fn *, ms_cl_fn_new, (ms_cl *c)) \
  X(void, ms_cl_fn_free, (ms_cl_fn *f)) \
  X(const char *, ms_cl_fn_error, (ms_cl_fn *f)) \
  X(void, ms_cl_fn_begin, (ms_cl_fn *f, ms_cl_func func)) \
  X(int, ms_cl_fn_end, (ms_cl_fn *f)) \
  /* Waits for every queued function (ms_cl_func_info and ms_cl_func_ranges are valid after this): 0, or 1 with the first compile error (by declaration order) in ms_cl_error. */ \
  X(int, ms_cl_wait, (ms_cl *c))

#ifdef MS_CL_DYNAMIC
typedef struct {
#define MS_CL_MEMBER(ret, name, args) ret(*fn_##name) args;
  MS_CL_API(MS_CL_MEMBER)
#undef MS_CL_MEMBER
} ms_cl_api;
extern ms_cl_api ms_cl_fns;
#define ms_cl_new ms_cl_fns.fn_ms_cl_new
#define ms_cl_error ms_cl_fns.fn_ms_cl_error
#define ms_cl_free ms_cl_fns.fn_ms_cl_free
#define ms_cl_sig_new ms_cl_fns.fn_ms_cl_sig_new
#define ms_cl_sig_param ms_cl_fns.fn_ms_cl_sig_param
#define ms_cl_sig_ret ms_cl_fns.fn_ms_cl_sig_ret
#define ms_cl_declare_func ms_cl_fns.fn_ms_cl_declare_func
#define ms_cl_declare_data ms_cl_fns.fn_ms_cl_declare_data
#define ms_cl_define_data ms_cl_fns.fn_ms_cl_define_data
#define ms_cl_block_new ms_cl_fns.fn_ms_cl_block_new
#define ms_cl_block_param_add ms_cl_fns.fn_ms_cl_block_param_add
#define ms_cl_block_param ms_cl_fns.fn_ms_cl_block_param
#define ms_cl_entry ms_cl_fns.fn_ms_cl_entry
#define ms_cl_enter ms_cl_fns.fn_ms_cl_enter
#define ms_cl_seal ms_cl_fns.fn_ms_cl_seal
#define ms_cl_seal_all ms_cl_fns.fn_ms_cl_seal_all
#define ms_cl_cold ms_cl_fns.fn_ms_cl_cold
#define ms_cl_srcloc ms_cl_fns.fn_ms_cl_srcloc
#define ms_cl_stack_slot ms_cl_fns.fn_ms_cl_stack_slot
#define ms_cl_stack_addr ms_cl_fns.fn_ms_cl_stack_addr
#define ms_cl_sp ms_cl_fns.fn_ms_cl_sp
#define ms_cl_iconst ms_cl_fns.fn_ms_cl_iconst
#define ms_cl_f32const ms_cl_fns.fn_ms_cl_f32const
#define ms_cl_f64const ms_cl_fns.fn_ms_cl_f64const
#define ms_cl_unary ms_cl_fns.fn_ms_cl_unary
#define ms_cl_binary ms_cl_fns.fn_ms_cl_binary
#define ms_cl_ovf ms_cl_fns.fn_ms_cl_ovf
#define ms_cl_cast ms_cl_fns.fn_ms_cl_cast
#define ms_cl_icmp ms_cl_fns.fn_ms_cl_icmp
#define ms_cl_fcmp ms_cl_fns.fn_ms_cl_fcmp
#define ms_cl_select ms_cl_fns.fn_ms_cl_select
#define ms_cl_load ms_cl_fns.fn_ms_cl_load
#define ms_cl_load_ext ms_cl_fns.fn_ms_cl_load_ext
#define ms_cl_store ms_cl_fns.fn_ms_cl_store
#define ms_cl_store_trunc ms_cl_fns.fn_ms_cl_store_trunc
#define ms_cl_copy ms_cl_fns.fn_ms_cl_copy
#define ms_cl_copy_dyn ms_cl_fns.fn_ms_cl_copy_dyn
#define ms_cl_fill ms_cl_fns.fn_ms_cl_fill
#define ms_cl_atomic_load ms_cl_fns.fn_ms_cl_atomic_load
#define ms_cl_atomic_store ms_cl_fns.fn_ms_cl_atomic_store
#define ms_cl_atomic_rmw ms_cl_fns.fn_ms_cl_atomic_rmw
#define ms_cl_atomic_cas ms_cl_fns.fn_ms_cl_atomic_cas
#define ms_cl_fence ms_cl_fns.fn_ms_cl_fence
#define ms_cl_func_addr ms_cl_fns.fn_ms_cl_func_addr
#define ms_cl_data_addr ms_cl_fns.fn_ms_cl_data_addr
#define ms_cl_jump ms_cl_fns.fn_ms_cl_jump
#define ms_cl_brif ms_cl_fns.fn_ms_cl_brif
#define ms_cl_switch ms_cl_fns.fn_ms_cl_switch
#define ms_cl_ret ms_cl_fns.fn_ms_cl_ret
#define ms_cl_trap ms_cl_fns.fn_ms_cl_trap
#define ms_cl_call ms_cl_fns.fn_ms_cl_call
#define ms_cl_call_indirect ms_cl_fns.fn_ms_cl_call_indirect
#define ms_cl_dump ms_cl_fns.fn_ms_cl_dump
#define ms_cl_finish ms_cl_fns.fn_ms_cl_finish
#define ms_cl_func_info ms_cl_fns.fn_ms_cl_func_info
#define ms_cl_func_ranges ms_cl_fns.fn_ms_cl_func_ranges
#define ms_cl_dwarf_file ms_cl_fns.fn_ms_cl_dwarf_file
#define ms_cl_dwarf_dir ms_cl_fns.fn_ms_cl_dwarf_dir
#define ms_cl_func_name ms_cl_fns.fn_ms_cl_func_name
#define ms_cl_fn_new ms_cl_fns.fn_ms_cl_fn_new
#define ms_cl_fn_free ms_cl_fns.fn_ms_cl_fn_free
#define ms_cl_fn_error ms_cl_fns.fn_ms_cl_fn_error
#define ms_cl_fn_begin ms_cl_fns.fn_ms_cl_fn_begin
#define ms_cl_fn_end ms_cl_fns.fn_ms_cl_fn_end
#define ms_cl_wait ms_cl_fns.fn_ms_cl_wait

typedef void *(*ms_cl_resolver)(void *data, const char *name);
/* Fills the table; returns the first name the resolver could not find, or NULL. */
static inline const char *ms_cl_bind(ms_cl_resolver resolve, void *data) {
#define MS_CL_BIND(ret, name, args) \
  if (!(ms_cl_fns.fn_##name = (ret(*) args)resolve(data, #name))) return #name;
  MS_CL_API(MS_CL_BIND)
#undef MS_CL_BIND
  return NULL;
}
#ifdef MS_CL_DEFINE_API
ms_cl_api ms_cl_fns;
#endif
#else
#define MS_CL_PROTO(ret, name, args) ret name args;
MS_CL_API(MS_CL_PROTO)
#undef MS_CL_PROTO
#endif

/* Conveniences over the generic functions. */
#define MS_CL_UNOP(fn, op) static inline ms_cl_val ms_cl_##fn(ms_cl_fn *c, ms_cl_val x) { return ms_cl_unary(c, op, x); }
#define MS_CL_BINOP(fn, op) \
  static inline ms_cl_val ms_cl_##fn(ms_cl_fn *c, ms_cl_val x, ms_cl_val y) { return ms_cl_binary(c, op, x, y); }
MS_CL_UNOP(ineg, MS_CL_INEG) MS_CL_UNOP(bnot, MS_CL_BNOT) MS_CL_UNOP(clz, MS_CL_CLZ) MS_CL_UNOP(ctz, MS_CL_CTZ)
MS_CL_UNOP(popcnt, MS_CL_POPCNT) MS_CL_UNOP(fneg, MS_CL_FNEG) MS_CL_UNOP(fabs, MS_CL_FABS) MS_CL_UNOP(sqrt, MS_CL_SQRT)
MS_CL_UNOP(ceil, MS_CL_CEIL) MS_CL_UNOP(floor, MS_CL_FLOOR) MS_CL_UNOP(trunc, MS_CL_TRUNC)
MS_CL_UNOP(nearest, MS_CL_NEAREST)
MS_CL_BINOP(iadd, MS_CL_IADD) MS_CL_BINOP(isub, MS_CL_ISUB) MS_CL_BINOP(imul, MS_CL_IMUL) MS_CL_BINOP(sdiv, MS_CL_SDIV)
MS_CL_BINOP(udiv, MS_CL_UDIV) MS_CL_BINOP(srem, MS_CL_SREM) MS_CL_BINOP(urem, MS_CL_UREM) MS_CL_BINOP(band, MS_CL_BAND)
MS_CL_BINOP(bor, MS_CL_BOR) MS_CL_BINOP(bxor, MS_CL_BXOR) MS_CL_BINOP(ishl, MS_CL_ISHL) MS_CL_BINOP(sshr, MS_CL_SSHR)
MS_CL_BINOP(ushr, MS_CL_USHR) MS_CL_BINOP(rotl, MS_CL_ROTL) MS_CL_BINOP(rotr, MS_CL_ROTR)
MS_CL_BINOP(umulhi, MS_CL_UMULHI) MS_CL_BINOP(fadd, MS_CL_FADD) MS_CL_BINOP(fsub, MS_CL_FSUB)
MS_CL_BINOP(fmul, MS_CL_FMUL) MS_CL_BINOP(fdiv, MS_CL_FDIV)
#undef MS_CL_UNOP
#undef MS_CL_BINOP

static inline ms_cl_val ms_cl_i64const(ms_cl_fn *c, int64_t k) { return ms_cl_iconst(c, MS_CL_I64, k); }
static inline void ms_cl_ret1(ms_cl_fn *c, ms_cl_val v) { ms_cl_ret(c, &v, 1); }
static inline void ms_cl_ret0(ms_cl_fn *c) { ms_cl_ret(c, NULL, 0); }
static inline void ms_cl_jump0(ms_cl_fn *c, ms_cl_block to) { ms_cl_jump(c, to, NULL, 0); }
static inline void ms_cl_br(ms_cl_fn *c, ms_cl_val cond, ms_cl_block then, ms_cl_block els) {
  ms_cl_brif(c, cond, then, NULL, 0, els, NULL, 0);
}
/* A call with exactly one result. */
static inline ms_cl_val ms_cl_call1(ms_cl_fn *c, ms_cl_func f, const ms_cl_val *args, uint32_t n) {
  ms_cl_val r;
  ms_cl_call(c, f, args, n, &r);
  return r;
}
static inline ms_cl_val ms_cl_call_indirect1(ms_cl_fn *c, ms_cl_sig s, ms_cl_val callee, const ms_cl_val *args, uint32_t n) {
  ms_cl_val r;
  ms_cl_call_indirect(c, s, callee, args, n, &r);
  return r;
}
#ifdef __cplusplus
}
#endif
#endif
