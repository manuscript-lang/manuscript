/* The `strfast` pass: the common cases of the runtime's string functions run as a few instructions in the caller
 * instead of a call.
 *
 * Lowering declares the runtime functions with a role (`string_parse_int`, `string_contains`, `string_compare`,
 * `string_starts_with`, `string_ends_with`, `string_scalar_step`, `string_scalar_at`). Each role gets one generated
 * function marked `inline(always)`, shared by every call site, which does the common case itself and calls the
 * runtime function for the rest.
 *
 * A string is two words: an inline string (tag `01`, up to 15 bytes) holds its bytes in the words themselves, any
 * other string holds a data pointer and a length (src/runtime/include/ms_rt/string.h).
 *
 * - `parse_int`: an optional sign and up to eighteen ASCII digits, which cannot overflow.
 * - `contains`: a needle of one byte in a text of under 32 bytes is a scan (the character-class test
 *   `"#.SE".contains(c)`); a longer needle or text calls the runtime.
 * - `starts_with`, `ends_with`: an affix of up to sixteen bytes is compared with two overlapping reads (one to
 *   three bytes: three byte reads), so a short test needs no call and no `memcmp`.
 * - `eq`: two strings of the same length up to sixteen bytes are compared like an affix; others call the runtime.
 * - `compare`: -1, 0 or 1; two inline strings from at most two word compares, a prefix of up to sixteen bytes byte
 *   by byte or eight at a time; a longer one calls the runtime.
 * - `scalar_at`, `scalar_step`: an offset inside the text decodes in place (the lead byte fixes the width, and a
 *   string is valid UTF-8 so every continuation byte is in bounds); an offset outside the text, or a continuation
 *   byte, calls the runtime for the default or the fault. `scalar_step` answers `scalar << 3 | width`.
 * - `to_bytes`: an empty string is the empty bytes without a call (so a literal `"".to_bytes()` folds to constant
 *   zeros); any other string calls the runtime. */
#include "compiler/opt/opt_pass.h"
#include "compiler/opt/opt_build.h"

enum { SF_TAG_SHIFT = 62, SF_LEN_SHIFT = 56, SF_LEN_MASK = 0x7fffffff, SF_WORD = 8 };

static MirValue sf_const_cmp(MirBuilder *b, MirCc cc, MirValue x, int64_t y) {
  return mir_b_icmp(b, cc, x, mir_b_iconst(b, y));
}

static MirValue sf_slot_of(MirBuilder *b, MirValue text) {
  const MirValue slot = mir_b_emit(b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = MIR_STR}, MIR_PTR);
  const MirValue spill[2] = {slot, text};
  (void)mir_b_emit(b, MOP_Store, spill, 2, (MirImm){0}, MIR_NONE);
  return slot;
}

/* The data pointer and byte length of the string held in slot `s`. */
typedef struct SfBytes {
  MirValue data, len;
} SfBytes;

static SfBytes sf_bytes_of(MirBuilder *b, MirValue s) {
  const MirValue w0 = ob_load(b, s, 0, MIR_PTR);
  const MirValue w1 = ob_load(b, s, SF_WORD, MIR_INT);
  const MirValue is_inline = sf_const_cmp(b, MCC_EQ, ob_int(b, MOP_Ushr, w1, SF_TAG_SHIFT), 1);
  const MirValue shorter = ob_int(b, MOP_And, ob_int(b, MOP_Ushr, w1, SF_LEN_SHIFT), 15);
  const MirValue longer = ob_int(b, MOP_And, w1, SF_LEN_MASK);
  return (SfBytes){mir_b_select(b, is_inline, s, w0), mir_b_select(b, is_inline, shorter, longer)};
}

/* The byte at `p + i`, zero-extended. */
static MirValue sf_byte_at(MirBuilder *b, MirValue p, MirValue i) { return ob_loadu(b, ob_past(b, p, i), 1); }

static MirValue sf_byte_of_text(MirBuilder *b, MirValue text, MirValue at) {
  const MirValue args[2] = {text, at};
  return mir_b_emit(b, MOP_StrByte, args, 2, (MirImm){0}, MIR_INT);
}

/* The answer `v` in the function's own result type: a runtime `u8` that lowering declares as `uint8` or as `bool`. */
static MirValue sf_flag(MirBuilder *b, bool v) {
  if (b->func.ret == MIR_BOOL) {
    return mir_b_bconst(b, v);
  }
  const MirValue n = mir_b_iconst(b, v ? 1 : 0);
  return mir_b_emit(b, MOP_Conv, &n, 1, (MirImm){0}, b->func.ret);
}

static void sf_call_slow(MirBuilder *b, uint32_t slow_ext, const MirValue *args, uint32_t nargs) {
  mir_b_ret(b, mir_b_call_rt(b, slow_ext, args, nargs));
}

/* ---- parse_int ---- */

static void sf_parse_int(MirBuilder *b, uint32_t slow_ext) {
  MirValue ps[2];
  mir_b_params(b, ps, 2);
  const MirValue text = ps[0], out = ps[1];
  const MirBlock fail = mir_b_new_block(b), slow = mir_b_new_block(b), scan = mir_b_new_block(b);
  const MirBlock header = mir_b_new_block(b), body = mir_b_new_block(b), step = mir_b_new_block(b);
  const MirBlock done = mir_b_new_block(b), first = mir_b_new_block(b), long_check = mir_b_new_block(b);
  const SfBytes t = sf_bytes_of(b, sf_slot_of(b, text));
  const MirValue zero = mir_b_iconst(b, 0), one = mir_b_iconst(b, 1);
  mir_b_br_if(b, mir_b_icmp(b, MCC_EQ, t.len, zero), fail, NULL, 0, first, NULL, 0);
  mir_b_seal_block(b, first);
  mir_b_switch_to(b, first);
  const MirValue c0 = sf_byte_at(b, t.data, zero);
  const MirValue minus = sf_const_cmp(b, MCC_EQ, c0, '-');
  const MirValue plus = sf_const_cmp(b, MCC_EQ, c0, '+');
  const MirValue yes = mir_b_bconst(b, true);
  const MirValue has_sign = mir_b_select(b, minus, yes, plus);
  const MirValue start = mir_b_select(b, has_sign, one, zero);
  const MirValue n = mir_b_binop(b, MOP_ISub, t.len, start);
  mir_b_br_if(b, mir_b_icmp(b, MCC_LE, n, zero), fail, NULL, 0, long_check, NULL, 0);
  mir_b_seal_block(b, long_check);
  mir_b_switch_to(b, long_check);
  ob_br_if(b, sf_const_cmp(b, MCC_GT, n, 18), slow, scan);
  mir_b_switch_to(b, scan);
  const MirVar acc = mir_b_declare_var(b, MIR_INT, MM_BORROW);
  const MirVar at = mir_b_declare_var(b, MIR_INT, MM_BORROW);
  mir_b_def_var(b, acc, zero);
  mir_b_def_var(b, at, start);
  mir_b_br(b, header, NULL, 0);
  mir_b_switch_to(b, header);
  const MirValue i = mir_b_use_var(b, at);
  ob_br_if(b, mir_b_icmp(b, MCC_LT, i, t.len), body, done);
  mir_b_switch_to(b, body);
  const MirValue digit = ob_int(b, MOP_ISub, sf_byte_at(b, t.data, i), '0');
  const MirValue below = mir_b_icmp(b, MCC_LT, digit, zero);
  const MirValue above = sf_const_cmp(b, MCC_GT, digit, 9);
  mir_b_br_if(b, mir_b_select(b, below, yes, above), fail, NULL, 0, step, NULL, 0);
  mir_b_seal_block(b, step);
  mir_b_switch_to(b, step);
  const MirValue sum = mir_b_binop(b, MOP_IAdd, ob_int(b, MOP_IMul, mir_b_use_var(b, acc), 10), digit);
  mir_b_def_var(b, acc, sum);
  mir_b_def_var(b, at, ob_int(b, MOP_IAdd, i, 1));
  mir_b_br(b, header, NULL, 0);
  mir_b_seal_block(b, header);
  mir_b_seal_block(b, fail);
  mir_b_switch_to(b, fail);
  mir_b_ret(b, sf_flag(b, false));
  mir_b_switch_to(b, slow);
  const MirValue rest[2] = {text, out};
  sf_call_slow(b, slow_ext, rest, 2);
  mir_b_switch_to(b, done);
  const MirValue magnitude = mir_b_use_var(b, acc);
  const MirValue negated = mir_b_emit(b, MOP_INeg, &magnitude, 1, (MirImm){0}, MIR_INT);
  const MirValue pair[2] = {out, mir_b_select(b, minus, negated, magnitude)};
  (void)mir_b_emit(b, MOP_Store, pair, 2, (MirImm){0}, MIR_NONE);
  mir_b_ret(b, sf_flag(b, true));
}

/* ---- contains ---- */

static void sf_contains(MirBuilder *b, uint32_t slow_ext) {
  MirValue ps[2];
  mir_b_params(b, ps, 2);
  const MirValue hay = ps[0], needle = ps[1];
  const MirBlock slow = mir_b_new_block(b), header = mir_b_new_block(b), body = mir_b_new_block(b);
  const MirBlock step = mir_b_new_block(b), hit = mir_b_new_block(b), miss = mir_b_new_block(b);
  const MirBlock one_byte = mir_b_new_block(b);
  const SfBytes h = sf_bytes_of(b, sf_slot_of(b, hay));
  const SfBytes n = sf_bytes_of(b, sf_slot_of(b, needle));
  const MirValue fits = ob_and(b, sf_const_cmp(b, MCC_LT, h.len, 32), sf_const_cmp(b, MCC_EQ, n.len, 1));
  ob_br_if(b, fits, one_byte, slow);
  mir_b_switch_to(b, one_byte);
  const MirValue zero = mir_b_iconst(b, 0);
  const MirValue c = sf_byte_at(b, n.data, zero);
  const MirVar at = mir_b_declare_var(b, MIR_INT, MM_BORROW);
  mir_b_def_var(b, at, zero);
  mir_b_br(b, header, NULL, 0);
  mir_b_switch_to(b, header);
  const MirValue i = mir_b_use_var(b, at);
  ob_br_if(b, mir_b_icmp(b, MCC_LT, i, h.len), body, miss);
  mir_b_switch_to(b, body);
  ob_br_if(b, mir_b_icmp(b, MCC_EQ, sf_byte_at(b, h.data, i), c), hit, step);
  mir_b_switch_to(b, step);
  mir_b_def_var(b, at, ob_int(b, MOP_IAdd, i, 1));
  mir_b_br(b, header, NULL, 0);
  mir_b_seal_block(b, header);
  mir_b_switch_to(b, hit);
  mir_b_ret(b, sf_flag(b, true));
  mir_b_switch_to(b, miss);
  mir_b_ret(b, sf_flag(b, false));
  mir_b_switch_to(b, slow);
  const MirValue rest[2] = {hay, needle};
  sf_call_slow(b, slow_ext, rest, 2);
}

/* ---- scalar_at, scalar_step ---- */

/* Decodes the multi-byte scalar whose lead byte `b0` (at least 0x80) is at `offset` of `text`; each path returns
 * the scalar, or for a step `scalar << 3 | width`. A continuation byte in the lead position goes to `slow`. */
static void sf_return_scalar(MirBuilder *b, MirValue scalar, int64_t width, bool step) {
  mir_b_ret(b, step ? ob_int(b, MOP_Or, ob_int(b, MOP_Shl, scalar, 3), width) : scalar);
}

static MirValue sf_continuation(MirBuilder *b, MirValue text, MirValue offset, int64_t k) {
  return ob_int(b, MOP_And, sf_byte_of_text(b, text, ob_int(b, MOP_IAdd, offset, k)), 0x3F);
}

static void sf_decode(MirBuilder *b, MirValue text, MirValue offset, MirValue b0, MirBlock slow, bool step) {
  const MirBlock lead_ok = mir_b_new_block(b), two = mir_b_new_block(b), wide = mir_b_new_block(b);
  const MirBlock three = mir_b_new_block(b), four = mir_b_new_block(b);
  /* 0x80..0xBF is a continuation byte: the offset is inside a scalar. */
  mir_b_br_if(b, sf_const_cmp(b, MCC_GE, b0, 0xC0), lead_ok, NULL, 0, slow, NULL, 0);
  mir_b_seal_block(b, lead_ok);
  mir_b_switch_to(b, lead_ok);
  ob_br_if(b, sf_const_cmp(b, MCC_LT, b0, 0xE0), two, wide);
  mir_b_switch_to(b, two);
  MirValue r = mir_b_binop(b, MOP_Or, ob_int(b, MOP_Shl, ob_int(b, MOP_And, b0, 0x1F), 6), sf_continuation(b, text, offset, 1));
  sf_return_scalar(b, r, 2, step);
  mir_b_switch_to(b, wide);
  ob_br_if(b, sf_const_cmp(b, MCC_LT, b0, 0xF0), three, four);
  mir_b_switch_to(b, three);
  const MirValue x = ob_int(b, MOP_Shl, ob_int(b, MOP_And, b0, 0x0F), 12);
  const MirValue y = ob_int(b, MOP_Shl, sf_continuation(b, text, offset, 1), 6);
  r = mir_b_binop(b, MOP_Or, mir_b_binop(b, MOP_Or, x, y), sf_continuation(b, text, offset, 2));
  sf_return_scalar(b, r, 3, step);
  mir_b_switch_to(b, four);
  const MirValue w = ob_int(b, MOP_Shl, ob_int(b, MOP_And, b0, 0x07), 18);
  const MirValue x4 = ob_int(b, MOP_Shl, sf_continuation(b, text, offset, 1), 12);
  const MirValue y4 = ob_int(b, MOP_Shl, sf_continuation(b, text, offset, 2), 6);
  r = mir_b_binop(b, MOP_Or, mir_b_binop(b, MOP_Or, mir_b_binop(b, MOP_Or, w, x4), y4), sf_continuation(b, text, offset, 3));
  sf_return_scalar(b, r, 4, step);
}

/* `scalar_at(text, offset, has, default)`, or `scalar_step(text, offset)` answering `scalar << 3 | width`. Both read a
 * byte only for an offset inside the text. */
static void sf_scalar(MirBuilder *b, uint32_t slow_ext, bool step) {
  MirValue ps[4];
  mir_b_params(b, ps, step ? 2 : 4);
  const MirValue text = ps[0], offset = ps[1];
  const MirBlock slow = mir_b_new_block(b), ascii = mir_b_new_block(b), multi = mir_b_new_block(b);
  /* An offset outside the text is the runtime's to answer (an invalid byte, or the default): no byte is read for it. */
  const MirBlock read = mir_b_new_block(b);
  const MirValue len = mir_b_emit(b, MOP_StrBytes, &text, 1, (MirImm){0}, MIR_INT);
  const MirValue inside = ob_and(b, sf_const_cmp(b, MCC_GE, offset, 0), mir_b_icmp(b, MCC_LT, offset, len));
  mir_b_br_if(b, inside, read, NULL, 0, slow, NULL, 0);
  mir_b_seal_block(b, read);
  mir_b_switch_to(b, read);
  const MirValue b0 = sf_byte_of_text(b, text, offset);
  ob_br_if(b, sf_const_cmp(b, MCC_LT, b0, 128), ascii, multi);
  mir_b_switch_to(b, ascii);
  mir_b_ret(b, step ? ob_int(b, MOP_Or, ob_int(b, MOP_Shl, b0, 3), 1) : b0);
  mir_b_switch_to(b, multi);
  sf_decode(b, text, offset, b0, slow, step);
  mir_b_seal_block(b, slow);
  mir_b_switch_to(b, slow);
  sf_call_slow(b, slow_ext, ps, step ? 2 : 4);
}

static void sf_scalar_at(MirBuilder *b, uint32_t slow_ext) { sf_scalar(b, slow_ext, false); }

/* `scalar_text(text, offset)`: the scalar at a byte offset inside the text, as a string. A scalar is at most four
 * bytes, so the string is always inline: its two words are built here from the scalar's bytes and length (a
 * multi-byte scalar asks the runtime for them), with the tag a constant. Its users then compare words and read the
 * length without testing which kind of string they were given. The offset must be inside the text: the two callers,
 * the `chars` loop (`index < len`) and `Fields.next` (`i < n`), test it, as the runtime function does not. */
static void sf_scalar_text(MirBuilder *b, uint32_t slow_ext) {
  MirValue ps[2];
  mir_b_params(b, ps, 2);
  const MirBlock slow = mir_b_new_block(b), ascii = mir_b_new_block(b), join = mir_b_new_block(b);
  const MirValue bytes = mir_b_add_block_param(b, join, MIR_INT, MM_BORROW);
  const MirValue length = mir_b_add_block_param(b, join, MIR_INT, MM_BORROW);
  const MirValue b0 = sf_byte_of_text(b, ps[0], ps[1]);
  ob_br_if(b, sf_const_cmp(b, MCC_LT, b0, 128), ascii, slow);
  mir_b_switch_to(b, ascii);
  const MirValue ascii_words[2] = {b0, mir_b_iconst(b, 1)};
  mir_b_br(b, join, ascii_words, 2);
  mir_b_seal_block(b, slow);
  mir_b_switch_to(b, slow);
  const MirValue scalar = mir_b_call_rt(b, slow_ext, ps, 2);
  const MirValue made = sf_slot_of(b, scalar);
  const MirValue made_words[2] = {ob_load(b, made, 0, MIR_INT),
                                  ob_int(b, MOP_And, ob_int(b, MOP_Ushr, ob_load(b, made, SF_WORD, MIR_INT), SF_LEN_SHIFT), 15)};
  (void)mir_b_emit(b, MOP_Drop, &scalar, 1, (MirImm){0}, MIR_NONE); /* an inline string: its words are copied above */
  mir_b_br(b, join, made_words, 2);
  mir_b_seal_block(b, join);
  mir_b_switch_to(b, join);
  const MirValue out = mir_b_emit(b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = MIR_STR}, MIR_PTR);
  const MirValue low[2] = {out, bytes};
  (void)mir_b_emit(b, MOP_Store, low, 2, (MirImm){0}, MIR_NONE);
  const MirValue tagged = mir_b_binop(b, MOP_Or, mir_b_iconst(b, (int64_t)(UINT64_C(1) << SF_TAG_SHIFT)),
                                      ob_int(b, MOP_Shl, length, SF_LEN_SHIFT));
  const MirValue high[2] = {ob_add(b, out, SF_WORD), tagged};
  (void)mir_b_emit(b, MOP_Store, high, 2, (MirImm){0}, MIR_NONE);
  mir_b_ret(b, mir_b_emit(b, MOP_Take, &out, 1, (MirImm){.tag = MI_TY, .a = MIR_STR}, MIR_STR));
}
static void sf_scalar_step(MirBuilder *b, uint32_t slow_ext) { sf_scalar(b, slow_ext, true); }

/* ---- to_bytes ---- */

static void sf_to_bytes(MirBuilder *b, uint32_t slow_ext) {
  MirValue ps[1];
  mir_b_params(b, ps, 1);
  const MirBlock empty = mir_b_new_block(b), slow = mir_b_new_block(b);
  const SfBytes text = sf_bytes_of(b, sf_slot_of(b, ps[0]));
  ob_br_if(b, sf_const_cmp(b, MCC_EQ, text.len, 0), empty, slow);
  mir_b_switch_to(b, empty);
  /* The empty bytes: a null data pointer, length 0 and capacity 0, owning nothing. */
  const MirValue made = mir_b_emit(b, MOP_Slot, NULL, 0, (MirImm){.tag = MI_TY, .a = MIR_BYTES}, MIR_PTR);
  const MirValue zero = mir_b_iconst(b, 0);
  for (int64_t word = 0; word < 3; word++) {
    const MirValue store[2] = {ob_add(b, made, word * SF_WORD), zero};
    (void)mir_b_emit(b, MOP_Store, store, 2, (MirImm){0}, MIR_NONE);
  }
  mir_b_ret(b, mir_b_emit(b, MOP_Take, &made, 1, (MirImm){.tag = MI_TY, .a = MIR_BYTES}, MIR_BYTES));
  mir_b_switch_to(b, slow);
  sf_call_slow(b, slow_ext, ps, 1);
}

/* ---- starts_with, ends_with ---- */

/* The first difference of the bytes at `x` and `y` for `n` in `w..=2 * w`: two overlapping reads of `w` bytes, the
 * first at 0 and the last ending at `n`. Zero when every byte is equal. */
static MirValue sf_diff_overlapping(MirBuilder *b, MirValue x, MirValue y, MirValue n, int64_t w) {
  const MirValue zero = mir_b_iconst(b, 0);
  const MirValue back = ob_int(b, MOP_ISub, n, w);
  const MirValue head = mir_b_binop(b, MOP_Xor, ob_loadu(b, ob_past(b, x, zero), w), ob_loadu(b, ob_past(b, y, zero), w));
  const MirValue tail = mir_b_binop(b, MOP_Xor, ob_loadu(b, ob_past(b, x, back), w), ob_loadu(b, ob_past(b, y, back), w));
  return mir_b_binop(b, MOP_Or, head, tail);
}

static void sf_return_same(MirBuilder *b, MirValue diff) {
  mir_b_ret(b, mir_b_icmp(b, MCC_EQ, diff, mir_b_iconst(b, 0)));
}

/* `end` selects the text's last bytes, `equal` makes the two strings the same length (`==`) instead of a prefix. */
static void sf_affix(MirBuilder *b, uint32_t slow_ext, bool end, bool equal) {
  MirValue ps[2];
  mir_b_params(b, ps, 2);
  const MirValue text = ps[0], part = ps[1];
  const MirBlock slow = mir_b_new_block(b), fits = mir_b_new_block(b), empty = mir_b_new_block(b);
  const MirBlock wide = mir_b_new_block(b), mid = mir_b_new_block(b), tiny = mir_b_new_block(b);
  const MirBlock no = mir_b_new_block(b), check = mir_b_new_block(b);
  const MirBlock four_check = mir_b_new_block(b), four = mir_b_new_block(b);
  const MirValue text_slot = sf_slot_of(b, text), part_slot = sf_slot_of(b, part);
  if (equal) { /* two inline strings are equal exactly when their words are: the bytes past the length are zero */
    const MirBlock both = mir_b_new_block(b), other = mir_b_new_block(b);
    const MirValue tw1 = ob_load(b, text_slot, SF_WORD, MIR_INT), pw1 = ob_load(b, part_slot, SF_WORD, MIR_INT);
    const MirValue text_inline = sf_const_cmp(b, MCC_EQ, ob_int(b, MOP_Ushr, tw1, SF_TAG_SHIFT), 1);
    const MirValue part_inline = sf_const_cmp(b, MCC_EQ, ob_int(b, MOP_Ushr, pw1, SF_TAG_SHIFT), 1);
    ob_br_if(b, mir_b_select(b, text_inline, part_inline, mir_b_bconst(b, false)), both, other);
    mir_b_switch_to(b, both);
    const MirValue tw0 = ob_load(b, text_slot, 0, MIR_INT), pw0 = ob_load(b, part_slot, 0, MIR_INT);
    const MirValue same_low = mir_b_icmp(b, MCC_EQ, tw0, pw0);
    mir_b_ret(b, mir_b_select(b, same_low, mir_b_icmp(b, MCC_EQ, tw1, pw1), mir_b_bconst(b, false)));
    mir_b_switch_to(b, other);
  }
  const SfBytes t = sf_bytes_of(b, text_slot);
  const SfBytes p = sf_bytes_of(b, part_slot);
  ob_br_if(b, mir_b_icmp(b, equal ? MCC_NE : MCC_GT, p.len, t.len), no, check);
  mir_b_switch_to(b, check);
  ob_br_if(b, sf_const_cmp(b, MCC_GT, p.len, 16), slow, fits);
  mir_b_switch_to(b, fits);
  /* The window of the text to compare: its first or last `p.len` bytes. */
  const MirValue zero = mir_b_iconst(b, 0);
  const MirValue window = ob_past(b, t.data, end ? mir_b_binop(b, MOP_ISub, t.len, p.len) : zero);
  ob_br_if(b, mir_b_icmp(b, MCC_EQ, p.len, zero), empty, mid);
  mir_b_switch_to(b, mid);
  ob_br_if(b, sf_const_cmp(b, MCC_GE, p.len, 8), wide, four_check);
  mir_b_switch_to(b, four_check);
  ob_br_if(b, sf_const_cmp(b, MCC_GE, p.len, 4), four, tiny);
  mir_b_switch_to(b, wide);
  sf_return_same(b, sf_diff_overlapping(b, window, p.data, p.len, 8));
  mir_b_switch_to(b, four);
  sf_return_same(b, sf_diff_overlapping(b, window, p.data, p.len, 4));
  mir_b_switch_to(b, tiny); /* one to three bytes: the first, the middle and the last */
  const MirValue half = ob_int(b, MOP_Ushr, p.len, 1);
  const MirValue last = ob_int(b, MOP_ISub, p.len, 1);
  const MirValue ks[3] = {zero, half, last};
  MirValue diff = zero;
  for (uint32_t k = 0; k < 3; k++) {
    diff = mir_b_binop(b, MOP_Or, diff, mir_b_binop(b, MOP_Xor, sf_byte_at(b, window, ks[k]), sf_byte_at(b, p.data, ks[k])));
  }
  sf_return_same(b, diff);
  mir_b_switch_to(b, empty);
  mir_b_ret(b, mir_b_bconst(b, true));
  mir_b_switch_to(b, no);
  mir_b_ret(b, mir_b_bconst(b, false));
  mir_b_switch_to(b, slow);
  sf_call_slow(b, slow_ext, ps, 2);
}

static void sf_starts_with(MirBuilder *b, uint32_t slow_ext) { sf_affix(b, slow_ext, false, false); }
static void sf_ends_with(MirBuilder *b, uint32_t slow_ext) { sf_affix(b, slow_ext, true, false); }
static void sf_equal(MirBuilder *b, uint32_t slow_ext) { sf_affix(b, slow_ext, false, true); }

/* ---- compare ---- */

/* The first differing byte of the words `dx` and `dy` (whose difference is `dd`, not zero) decides, lowest first. */
static void sf_decide_word(MirBuilder *b, MirValue dx, MirValue dy, MirValue dd, MirValue minus, MirValue plus) {
  const MirValue low = mir_b_emit(b, MOP_Ctz, &dd, 1, (MirImm){0}, MIR_INT);
  const MirValue shift = ob_int(b, MOP_And, low, -8);
  const MirValue xb = ob_int(b, MOP_And, mir_b_binop(b, MOP_Ushr, dx, shift), 255);
  const MirValue yb = ob_int(b, MOP_And, mir_b_binop(b, MOP_Ushr, dy, shift), 255);
  mir_b_ret(b, mir_b_select(b, mir_b_icmp(b, MCC_LT, xb, yb), minus, plus));
}

/* Both strings inline (up to 15 bytes, zero past the length): the bytes are the words themselves, so the first
 * differing byte comes from at most two word compares with no length decode. Else continues in `general`. */
static void sf_compare_inline(MirBuilder *b, MirValue sx, MirValue sy, MirBlock wdiff, MirBlock general,
               MirValue minus, MirValue plus) {
  const MirBlock inl = mir_b_new_block(b), inl2 = mir_b_new_block(b), lens = mir_b_new_block(b);
  const MirValue x0 = ob_load(b, sx, 0, MIR_INT), x1 = ob_load(b, sx, SF_WORD, MIR_INT);
  const MirValue y0 = ob_load(b, sy, 0, MIR_INT), y1 = ob_load(b, sy, SF_WORD, MIR_INT);
  const MirValue nx = ob_int(b, MOP_Xor, ob_int(b, MOP_Ushr, x1, SF_TAG_SHIFT), 1);
  const MirValue ny = ob_int(b, MOP_Xor, ob_int(b, MOP_Ushr, y1, SF_TAG_SHIFT), 1);
  const MirValue inline_pair = sf_const_cmp(b, MCC_EQ, mir_b_binop(b, MOP_Or, nx, ny), 0);
  ob_br_if(b, inline_pair, inl, general);
  mir_b_switch_to(b, inl);
  const MirValue first = mir_b_binop(b, MOP_Xor, x0, y0);
  const MirValue first_args[3] = {x0, y0, first};
  mir_b_br_if(b, sf_const_cmp(b, MCC_EQ, first, 0), inl2, NULL, 0, wdiff, first_args, 3);
  mir_b_seal_block(b, inl2);
  mir_b_switch_to(b, inl2);
  /* The second word holds seven bytes (bits 0 to 55), then the length and the tag. */
  const int64_t bytes_mask = ((int64_t)1 << SF_LEN_SHIFT) - 1;
  const MirValue m1 = ob_int(b, MOP_And, x1, bytes_mask), m2 = ob_int(b, MOP_And, y1, bytes_mask);
  const MirValue second = mir_b_binop(b, MOP_Xor, m1, m2);
  const MirValue second_args[3] = {m1, m2, second};
  mir_b_br_if(b, sf_const_cmp(b, MCC_EQ, second, 0), lens, NULL, 0, wdiff, second_args, 3);
  mir_b_seal_block(b, lens);
  mir_b_switch_to(b, lens);
  const MirValue lx = ob_int(b, MOP_And, ob_int(b, MOP_Ushr, x1, SF_LEN_SHIFT), 15);
  const MirValue ly = ob_int(b, MOP_And, ob_int(b, MOP_Ushr, y1, SF_LEN_SHIFT), 15);
  const MirValue more_or_same = mir_b_select(b, mir_b_icmp(b, MCC_GT, lx, ly), plus, mir_b_iconst(b, 0));
  mir_b_ret(b, mir_b_select(b, mir_b_icmp(b, MCC_LT, lx, ly), minus, more_or_same));
}

/* The pieces of `sf_compare` that share its blocks and operands. */
typedef struct SfCompare {
  MirBuilder *b;
  MirBlock head, body, step, tail, wdiff;
  MirValue minus, plus, n, shorter;
  SfBytes xs, ys;
} SfCompare;

/* Eight bytes at a time while a whole word remains in both strings; the first differing word is decided by its
 * lowest differing byte (little endian). Falls to `head` for the rest. */
static void sf_compare_words(const SfCompare *c) {
  MirBuilder *b = c->b;
  const MirBlock head = c->head, wdiff = c->wdiff;
  const MirValue n = c->n;
  const SfBytes xs = c->xs, ys = c->ys;
  const MirBlock whead = mir_b_new_block(b), wbody = mir_b_new_block(b), wstep = mir_b_new_block(b);
  const MirValue w = mir_b_add_block_param(b, whead, MIR_INT, MM_BORROW);
  const MirValue zero = mir_b_iconst(b, 0);
  mir_b_br(b, whead, &zero, 1);
  mir_b_switch_to(b, whead);
  const MirValue end = ob_int(b, MOP_IAdd, w, 8);
  mir_b_br_if(b, mir_b_icmp(b, MCC_LE, end, n), wbody, NULL, 0, head, &w, 1);
  mir_b_seal_block(b, wbody);
  mir_b_switch_to(b, wbody);
  const MirValue xw = ob_loadu(b, ob_past(b, xs.data, w), 8), yw = ob_loadu(b, ob_past(b, ys.data, w), 8);
  const MirValue diff = mir_b_binop(b, MOP_Xor, xw, yw);
  const MirValue word_args[3] = {xw, yw, diff};
  mir_b_br_if(b, mir_b_icmp(b, MCC_EQ, diff, zero), wstep, NULL, 0, wdiff, word_args, 3);
  mir_b_seal_block(b, wstep);
  mir_b_seal_block(b, wdiff);
  mir_b_switch_to(b, wstep);
  mir_b_br(b, whead, &end, 1);
  mir_b_seal_block(b, whead);
}

/* The rest byte by byte; equal prefixes make the shorter string the smaller. */
static void sf_compare_bytes(const SfCompare *c, MirValue i) {
  MirBuilder *b = c->b;
  const MirBlock head = c->head, body = c->body, step = c->step, tail = c->tail;
  const MirValue minus = c->minus, plus = c->plus, n = c->n, shorter = c->shorter;
  const SfBytes xs = c->xs, ys = c->ys;
  mir_b_switch_to(b, head);
  ob_br_if(b, mir_b_icmp(b, MCC_LT, i, n), body, tail);
  mir_b_switch_to(b, body);
  const MirValue xb = sf_byte_at(b, xs.data, i), yb = sf_byte_at(b, ys.data, i);
  const MirBlock differ = mir_b_new_block(b);
  ob_br_if(b, mir_b_icmp(b, MCC_EQ, xb, yb), step, differ);
  mir_b_switch_to(b, differ);
  mir_b_ret(b, mir_b_select(b, mir_b_icmp(b, MCC_LT, xb, yb), minus, plus));
  mir_b_switch_to(b, step);
  const MirValue next = ob_int(b, MOP_IAdd, i, 1);
  mir_b_br(b, head, &next, 1);
  mir_b_seal_block(b, head);
  /* Equal prefixes: the shorter string is smaller. */
  mir_b_switch_to(b, tail);
  const MirValue zero = mir_b_iconst(b, 0);
  const MirValue tail_cmp = mir_b_select(b, mir_b_icmp(b, MCC_GT, xs.len, ys.len), plus, zero);
  mir_b_ret(b, mir_b_select(b, shorter, minus, tail_cmp));
}

static void sf_compare(MirBuilder *b, uint32_t slow_ext) {
  MirValue ps[2];
  mir_b_params(b, ps, 2);
  const MirValue x = ps[0], y = ps[1];
  const MirBlock scan = mir_b_new_block(b), slow = mir_b_new_block(b), head = mir_b_new_block(b);
  const MirBlock body = mir_b_new_block(b), step = mir_b_new_block(b), tail = mir_b_new_block(b);
  const MirBlock general = mir_b_new_block(b), wdiff = mir_b_new_block(b);
  const MirValue minus = mir_b_iconst(b, -1), plus = mir_b_iconst(b, 1);
  const MirValue sx = sf_slot_of(b, x), sy = sf_slot_of(b, y);
  const MirValue dx = mir_b_add_block_param(b, wdiff, MIR_INT, MM_BORROW);
  const MirValue dy = mir_b_add_block_param(b, wdiff, MIR_INT, MM_BORROW);
  const MirValue dd = mir_b_add_block_param(b, wdiff, MIR_INT, MM_BORROW);
  sf_compare_inline(b, sx, sy, wdiff, general, minus, plus);
  mir_b_switch_to(b, wdiff);
  sf_decide_word(b, dx, dy, dd, minus, plus);
  mir_b_switch_to(b, general);
  const SfBytes xs = sf_bytes_of(b, sx), ys = sf_bytes_of(b, sy);
  const MirValue shorter = mir_b_icmp(b, MCC_LT, xs.len, ys.len);
  const MirValue n = mir_b_select(b, shorter, xs.len, ys.len);
  ob_br_if(b, sf_const_cmp(b, MCC_GT, n, 16), slow, scan);
  mir_b_switch_to(b, slow);
  sf_call_slow(b, slow_ext, ps, 2);
  mir_b_switch_to(b, scan);
  const MirValue i = mir_b_add_block_param(b, head, MIR_INT, MM_BORROW);
  const SfCompare c = {b, head, body, step, tail, wdiff, minus, plus, n, shorter, xs, ys};
  sf_compare_words(&c);
  sf_compare_bytes(&c, i);
}

/* ---- the pass ---- */

typedef struct SfKind {
  uint8_t role;
  const char *name;
  uint32_t nparams;
  MirTy params[4];
  MirTy ret;
  void (*build)(MirBuilder *b, uint32_t slow_ext);
} SfKind;

static const SfKind sf_kinds[] = {
  {MR_STRING_PARSE_INT, "parse_int", 2, {MIR_STR, MIR_PTR}, MIR_BOOL, sf_parse_int},
  {MR_STRING_CONTAINS, "contains_byte", 2, {MIR_STR, MIR_STR}, MIR_BOOL, sf_contains},
  {MR_STRING_STARTS_WITH, "starts_with", 2, {MIR_STR, MIR_STR}, MIR_BOOL, sf_starts_with},
  {MR_STRING_ENDS_WITH, "ends_with", 2, {MIR_STR, MIR_STR}, MIR_BOOL, sf_ends_with},
  {MR_STRING_EQ, "string_equal", 2, {MIR_STR, MIR_STR}, MIR_BOOL, sf_equal},
  {MR_STRING_COMPARE, "string_compare", 2, {MIR_STR, MIR_STR}, MIR_INT, sf_compare},
  {MR_STRING_SCALAR_STEP, "scalar_step", 2, {MIR_STR, MIR_INT}, MIR_INT, sf_scalar_step},
  {MR_STRING_SCALAR_TEXT, "scalar_text", 2, {MIR_STR, MIR_INT}, MIR_STR, sf_scalar_text},
  {MR_STRING_TO_BYTES, "to_bytes", 1, {MIR_STR}, MIR_BYTES, sf_to_bytes},
  {MR_STRING_SCALAR_AT, "scalar_at", 4, {MIR_STR, MIR_INT, MIR_BOOL, MIR_INT}, MIR_INT, sf_scalar_at},
};

static const SfKind *sf_kind_of(const MirExtern *e) {
  for (uint32_t k = 0; k < sizeof sf_kinds / sizeof *sf_kinds; k++) {
    const SfKind *kind = &sf_kinds[k];
    const bool flag = kind->ret == MIR_BOOL && e->ret == MIR_UINT8; /* a `u8` answer declared as uint8 */
    if (kind->role != e->role || kind->nparams != e->nparams || (kind->ret != e->ret && !flag)) {
      continue;
    }
    bool same = true;
    for (uint32_t p = 0; p < kind->nparams; p++) {
      same = same && kind->params[p] == e->params[p].ty;
    }
    return same ? kind : NULL;
  }
  return NULL;
}

static uint32_t sf_build(MirModule *m, const SfKind *kind, uint32_t slow_ext, MirTy ret) {
  MirParam params[4];
  for (uint32_t p = 0; p < kind->nparams; p++) {
    params[p] = (MirParam){kind->params[p], MM_BORROW};
  }
  MirBuilder b;
  mir_b_init_fast_path(&b, m, mir_name(m, ms_span_of_text(kind->name)), params, kind->nparams, ret);
  kind->build(&b, slow_ext);
  uint32_t id = MIR_NONE;
  return mir_b_finish(&b, &id) ? id : MIR_NONE;
}

bool opt_strfast(MirModule *m) {
  const uint32_t original = (uint32_t)m->funcs.len; /* the helpers keep their own calls to the runtime */
  uint32_t helpers[sizeof sf_kinds / sizeof *sf_kinds];
  for (uint32_t k = 0; k < sizeof helpers / sizeof *helpers; k++) {
    helpers[k] = MIR_NONE;
  }
  bool changed = false;
  for (uint32_t fi = 0; fi < original; fi++) {
    for (uint32_t bi = 0; bi < m->funcs.ptr[fi].blocks.len; bi++) {
      for (uint32_t ii = 0; ii < m->funcs.ptr[fi].blocks.ptr[bi].insts.len; ii++) {
        MirInst *inst = &m->funcs.ptr[fi].blocks.ptr[bi].insts.ptr[ii];
        const SfKind *kind = inst->op == MOP_CallRt ? sf_kind_of(&m->externs.ptr[inst->imm.a]) : NULL;
        if (kind == NULL) {
          continue;
        }
        uint32_t *helper = &helpers[kind - sf_kinds];
        if (*helper == MIR_NONE) {
          *helper = sf_build(m, kind, inst->imm.a, m->externs.ptr[inst->imm.a].ret);
          inst = &m->funcs.ptr[fi].blocks.ptr[bi].insts.ptr[ii]; /* the function array may have moved */
        }
        if (*helper == MIR_NONE) {
          continue;
        }
        inst->op = MOP_Call;
        inst->imm = (MirImm){.tag = MI_FUNC, .a = *helper};
        changed = true;
      }
    }
  }
  return changed;
}
