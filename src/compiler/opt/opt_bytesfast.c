/* The `bytesfast` pass: a fixed-width read of a `Bytes` and a search for a byte run as a few instructions in the
 * caller instead of a runtime call.
 *
 * Lowering declares the runtime functions with a role (`bytes_read_word`, `bytes_index_of_byte`). Each gets one
 * generated function marked `inline(always)`, shared by every call site, which does the common case itself and
 * calls the runtime for the rest.
 *
 * `bytes_read_word(bytes, at, width, little, out) -> status`: with the offset in range and a little-endian read
 * (or one byte), one unaligned load into `out` and a zero status; a big-endian read and a bad width call the
 * runtime, and an offset out of range is status 2 (ERANGE) without a call.
 *
 * `bytes_index_of_byte(bytes, value, start, out) -> found`: the next sixteen bytes are searched two words at a time
 * (the zero-byte trick on the XOR with the byte repeated), so a field or line end a few bytes away is found without
 * a call. Fewer than sixteen bytes left, a value outside 0..=255 and a miss in the window go to the runtime, which
 * continues from where the window ended.
 *
 * The bytes are read through their memory form: data pointer, then length. */
#include "compiler/opt/opt_pass.h"
#include "compiler/opt/opt_build.h"

enum { BF_LEN = 8, BF_WINDOW = 16, BF_ERANGE = 2 };

/* The list through its memory form: spilled to a slot unless it already arrives as an address. */
static MirValue bf_memory(MirBuilder *b, MirValue bytes, MirTy ty) {
  if (ty == MIR_PTR) {
    return bytes;
  }
  const MirValue slot = mir_b_emit(b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = ty}, MIR_PTR);
  const MirValue spill[2] = {slot, bytes};
  (void)mir_b_emit(b, MOP_Store, spill, 2, (MirImm){0}, MIR_NONE);
  return slot;
}

/* `read_word`: the parameters are those of the runtime function, in order. */
static uint32_t bf_build_read_word(MirModule *m, uint32_t slow_ext, const MirExtern *e) {
  MirBuilder b;
  mir_b_init_fast_path(&b, m, mir_name(m, ms_span_of_text("bytes_read_word")), e->params, 5, e->ret);
  MirValue ps[5];
  mir_b_params(&b, ps, 5);
  const MirValue bytes = ps[0], at = ps[1], width = ps[2], little = ps[3], out = ps[4];
  const MirBlock check = mir_b_new_block(&b), fast = mir_b_new_block(&b), slow = mir_b_new_block(&b);
  const MirBlock fail = mir_b_new_block(&b), store = mir_b_new_block(&b);
  const MirValue loaded = mir_b_add_block_param(&b, store, MIR_INT, MM_BORROW);
  const MirValue vec = bf_memory(&b, bytes, e->params[0].ty);
  const MirValue len = ob_load(&b, vec, BF_LEN, MIR_INT);
  const MirValue zero = mir_b_iconst(&b, 0);
  const MirValue rest = mir_b_binop(&b, MOP_ISub, len, at);
  MirValue ok = ob_and(&b, mir_b_icmp(&b, MCC_GE, at, zero), mir_b_icmp(&b, MCC_LE, at, len));
  ok = ob_and(&b, ok, mir_b_icmp(&b, MCC_GE, rest, width));
  mir_b_br_if(&b, ok, check, NULL, 0, fail, NULL, 0);
  mir_b_seal_block(&b, check);
  mir_b_seal_block(&b, fail);
  mir_b_switch_to(&b, check);
  const MirValue single = mir_b_icmp(&b, MCC_EQ, width, mir_b_iconst(&b, 1));
  mir_b_br_if(&b, mir_b_binop(&b, MOP_Or, little, single), fast, NULL, 0, slow, NULL, 0);
  mir_b_seal_block(&b, fast);
  mir_b_seal_block(&b, slow);
  mir_b_switch_to(&b, fast);
  const MirValue p = ob_past(&b, ob_load(&b, vec, 0, MIR_PTR), at);
  static const int64_t widths[4] = {1, 2, 4, 8};
  MirBlock cases[4];
  MirCase switch_cases[4];
  for (uint32_t i = 0; i < 4; i++) {
    cases[i] = mir_b_new_block(&b);
    switch_cases[i] = (MirCase){widths[i], {cases[i], NULL, 0}};
  }
  mir_b_switch(&b, width, switch_cases, 4, slow);
  for (uint32_t i = 0; i < 4; i++) {
    mir_b_seal_block(&b, cases[i]);
    mir_b_switch_to(&b, cases[i]);
    const MirValue x = ob_loadu(&b, p, widths[i]);
    mir_b_br(&b, store, &x, 1);
  }
  mir_b_seal_block(&b, store);
  mir_b_switch_to(&b, store);
  const MirValue pair[2] = {out, loaded};
  (void)mir_b_emit(&b, MOP_Store, pair, 2, (MirImm){0}, MIR_NONE);
  mir_b_ret(&b, mir_b_iconst(&b, 0));
  mir_b_switch_to(&b, slow);
  const MirValue args[5] = {bytes, at, width, little, out};
  mir_b_ret(&b, mir_b_call_rt(&b, slow_ext, args, 5));
  mir_b_switch_to(&b, fail);
  mir_b_ret(&b, mir_b_iconst(&b, BF_ERANGE));
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}

/* Whether any byte of the eight at `p + off` equals the repeated value, and where: continues in `hit` with the
 * offset from the start of the bytes, else in `miss`. */
static void bf_probe(MirBuilder *b, MirValue p, MirValue repeated, MirValue from, int64_t off, MirBlock hit,
          MirBlock miss, const MirValue *miss_args, uint32_t nmiss) {
  const int64_t low7 = 0x7f7f7f7f7f7f7f7fLL, high = (int64_t)0x8080808080808080ULL;
  const MirValue word = ob_loadu(b, ob_add(b, p, off), 8);
  const MirValue x = mir_b_binop(b, MOP_Xor, word, repeated);
  /* The high bit of each byte of `y` is set unless that byte of `x` is zero. */
  MirValue y = ob_int(b, MOP_IAdd, ob_int(b, MOP_And, x, low7), low7);
  y = ob_int(b, MOP_And, mir_b_binop(b, MOP_Or, y, x), high);
  const MirValue t = ob_int(b, MOP_Xor, y, high);
  const MirValue none = mir_b_icmp(b, MCC_EQ, t, mir_b_iconst(b, 0));
  const MirValue tz = mir_b_emit(b, MOP_Ctz, &t, 1, (MirImm){0}, MIR_INT);
  const MirValue idx = ob_int(b, MOP_IAdd, ob_int(b, MOP_Ushr, tz, 3), off);
  const MirValue found_at = mir_b_binop(b, MOP_IAdd, from, idx);
  mir_b_br_if(b, none, miss, miss_args, nmiss, hit, &found_at, 1);
}

/* `index_of_byte`: the value is an `Int`, or a smaller integer converted to one. */
static uint32_t bf_build_index_of_byte(MirModule *m, uint32_t slow_ext, const MirExtern *e) {
  MirBuilder b;
  mir_b_init_fast_path(&b, m, mir_name(m, ms_span_of_text("bytes_index_of_byte")), e->params, 4, e->ret);
  MirValue ps[4];
  mir_b_params(&b, ps, 4);
  const MirValue bytes = ps[0], start = ps[2], out = ps[3];
  const MirBlock window = mir_b_new_block(&b), second = mir_b_new_block(&b), slow = mir_b_new_block(&b);
  const MirBlock found = mir_b_new_block(&b);
  const MirValue at = mir_b_add_block_param(&b, found, MIR_INT, MM_BORROW);
  const MirValue resume = mir_b_add_block_param(&b, slow, MIR_INT, MM_BORROW);
  MirValue value = ps[1];
  if (e->params[1].ty != MIR_INT) {
    value = mir_b_emit(&b, MOP_Conv, &value, 1, (MirImm){0}, MIR_INT);
  }
  const MirValue vec = bf_memory(&b, bytes, e->params[0].ty);
  const MirValue len = ob_load(&b, vec, BF_LEN, MIR_INT);
  const MirValue zero = mir_b_iconst(&b, 0);
  const MirValue from = mir_b_select(&b, mir_b_icmp(&b, MCC_LT, start, zero), zero, start);
  const MirValue room = mir_b_icmp(&b, MCC_GE, mir_b_binop(&b, MOP_ISub, len, from), mir_b_iconst(&b, BF_WINDOW));
  const MirValue byte = ob_and(&b, mir_b_icmp(&b, MCC_GE, value, zero), mir_b_icmp(&b, MCC_LE, value, mir_b_iconst(&b, 255)));
  mir_b_br_if(&b, ob_and(&b, room, byte), window, NULL, 0, slow, &start, 1);
  mir_b_seal_block(&b, window);
  mir_b_switch_to(&b, window);
  const MirValue p = ob_past(&b, ob_load(&b, vec, 0, MIR_PTR), from);
  const MirValue repeated = ob_int(&b, MOP_IMul, value, 0x0101010101010101LL);
  const MirValue after = ob_int(&b, MOP_IAdd, from, BF_WINDOW);
  bf_probe(&b, p, repeated, from, 0, found, second, NULL, 0);
  mir_b_seal_block(&b, second);
  mir_b_switch_to(&b, second);
  bf_probe(&b, p, repeated, from, 8, found, slow, &after, 1);
  mir_b_seal_block(&b, found);
  mir_b_switch_to(&b, found);
  const MirValue pair[2] = {out, at};
  (void)mir_b_emit(&b, MOP_Store, pair, 2, (MirImm){0}, MIR_NONE);
  mir_b_ret(&b, mir_b_bconst(&b, true));
  mir_b_seal_block(&b, slow);
  mir_b_switch_to(&b, slow); /* the runtime takes over from the end of the window, or from `start` when none */
  const MirValue args[4] = {bytes, ps[1], resume, out};
  mir_b_ret(&b, mir_b_call_rt(&b, slow_ext, args, 4));
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}

static bool bf_is_int(MirTy t) { return t == MIR_INT || t == MIR_UINT8; }

static bool bf_is_bytes(MirTy t) { return t == MIR_BYTES || t == MIR_PTR; }

static bool bf_shape(const MirExtern *e) {
  if (e->role == MR_BYTES_READ_WORD) {
    return e->nparams == 5 && e->ret == MIR_INT && bf_is_bytes(e->params[0].ty) && e->params[1].ty == MIR_INT &&
       e->params[2].ty == MIR_INT && e->params[3].ty == MIR_BOOL && e->params[4].ty == MIR_PTR;
  }
  if (e->role == MR_BYTES_INDEX_OF_BYTE) {
    return e->nparams == 4 && e->ret == MIR_BOOL && bf_is_bytes(e->params[0].ty) && bf_is_int(e->params[1].ty) &&
       e->params[2].ty == MIR_INT && e->params[3].ty == MIR_PTR;
  }
  return false;
}

/* One generated function per role and operand types. */
typedef struct BfHelper {
  uint8_t role;
  MirTy bytes, value;
  uint32_t func;
} BfHelper;

bool opt_bytesfast(MirModule *m) {
  const uint32_t original = (uint32_t)m->funcs.len; /* the helpers keep their own calls to the runtime */
  BfHelper *helpers = NULL;
  uint32_t nhelpers = 0, chelpers = 0;
  bool changed = false;
  for (uint32_t fi = 0; fi < original; fi++) {
    for (uint32_t bi = 0; bi < m->funcs.ptr[fi].blocks.len; bi++) {
      for (uint32_t ii = 0; ii < m->funcs.ptr[fi].blocks.ptr[bi].insts.len; ii++) {
        MirInst *inst = &m->funcs.ptr[fi].blocks.ptr[bi].insts.ptr[ii];
        if (inst->op != MOP_CallRt || !bf_shape(&m->externs.ptr[inst->imm.a])) {
          continue;
        }
        const MirExtern *e = &m->externs.ptr[inst->imm.a];
        const uint8_t role = e->role;
        const MirTy value = e->params[1].ty;
        uint32_t helper = MIR_NONE;
        for (uint32_t h = 0; h < nhelpers; h++) {
          if (helpers[h].role == role && helpers[h].bytes == e->params[0].ty && helpers[h].value == value) {
            helper = helpers[h].func;
          }
        }
        if (helper == MIR_NONE) {
          helper = role == MR_BYTES_READ_WORD ? bf_build_read_word(m, inst->imm.a, e)
                            : bf_build_index_of_byte(m, inst->imm.a, e);
          if (helper == MIR_NONE) {
            continue;
          }
          OPT_PUSH(&m->arena, helpers, nhelpers, chelpers, BfHelper, ((BfHelper){role, e->params[0].ty, value, helper}));
          inst = &m->funcs.ptr[fi].blocks.ptr[bi].insts.ptr[ii]; /* the function array may have moved */
        }
        inst->op = MOP_Call;
        inst->imm = (MirImm){.tag = MI_FUNC, .a = helper};
        changed = true;
      }
    }
  }
  return changed;
}
