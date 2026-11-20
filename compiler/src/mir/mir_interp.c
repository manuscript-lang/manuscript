/* The interpreter's driver: frames, control flow, faults with their cleanup, host functions and
 * the public entry points. Owns every MirInterp table; the module belongs to the caller. */
#include <stdlib.h>
#include <string.h>

#include "mir/mir_interp_impl.h"

typedef struct IpFrame {
    uint32_t func;
    MirVal *regs; /* owned: one value per SSA value of the function */
    uint32_t block;
    uint32_t ip;
    MirValue ret_dst; /* the caller's register for the result, or MIR_NONE */
} IpFrame;

typedef struct IpFrames {
    IpFrame *frames; /* owned */
    uint32_t count, capacity;
} IpFrames;

/* ---- host functions ---- */

static bool ip_host_fault(void *context, MsBuf *out, const MirVal *args, uint32_t nargs,
                          MirVal *result, MsStr *error) {
    MsBuf text = {0};
    (void)out;
    (void)result;
    if (nargs > 0) {
        ip_show(&text, args[0]);
    }
    MsArena *arena = context;
    *error = (MsStr){.ptr = ms_arena_strndup(arena, text.data == NULL ? "" : text.data, text.len),
                     .len = (uint32_t)text.len};
    ms_buf_free(&text);
    return false;
}

static bool ip_host_print(void *context, MsBuf *out, const MirVal *args, uint32_t nargs,
                          MirVal *result, MsStr *error) {
    (void)context;
    (void)result;
    (void)error;
    if (nargs > 0) {
        ip_show(out, args[0]);
    }
    ms_buf_putc(out, '\n');
    return true;
}

static bool ip_host_true(void *context, MsBuf *out, const MirVal *args, uint32_t nargs,
                         MirVal *result, MsStr *error) {
    (void)context; (void)out; (void)args; (void)nargs; (void)error;
    *result = mir_val_bool(true);
    return true;
}

static bool ip_host_void(void *context, MsBuf *out, const MirVal *args, uint32_t nargs,
                         MirVal *result, MsStr *error) {
    (void)context; (void)out; (void)args; (void)nargs; (void)error;
    *result = ip_void();
    return true;
}

static bool ip_host_zero(void *context, MsBuf *out, const MirVal *args, uint32_t nargs,
                         MirVal *result, MsStr *error) {
    (void)context; (void)out; (void)args; (void)nargs; (void)error;
    *result = mir_val_int(0);
    return true;
}

void mir_interp_register(MirInterp *interp, const char *name, MirHostFn fn, void *context) {
    for (uint32_t i = 0; i < interp->nhosts; i++) {
        if (strcmp(interp->hosts[i].name, name) == 0) {
            interp->hosts[i].fn = fn;
            interp->hosts[i].context = context;
            return;
        }
    }
    if (interp->nhosts == interp->chosts) {
        uint32_t grown = ip_grow_cap(interp->chosts, 16);
        interp->hosts = ip_regrow(interp->hosts, sizeof(IpHost) * interp->chosts, sizeof(IpHost) * grown);
        interp->chosts = grown;
    }
    interp->hosts[interp->nhosts++] =
        (IpHost){ms_arena_strndup(&interp->arena, name, strlen(name)), fn, context};
}

/* ---- construction ---- */

MirInterp *mir_interp_new(const MirModule *module) {
    MirInterp *it = calloc(1, sizeof *it);
    if (it == NULL) ip_oom();
    it->module = module;
    it->nstrings = module->strings.count;
    it->strings = calloc((size_t)it->nstrings + 1, sizeof(MirVal));
    it->globals = calloc((size_t)module->nglobals + 1, sizeof(MirVal));
    it->drop_cache = calloc((size_t)module->types.len + 1, 1);
    if (it->strings == NULL || it->globals == NULL || it->drop_cache == NULL) ip_oom();
    for (uint32_t i = 0; i < it->nstrings; i++) {
        MsStr text = ms_name(&module->strings, i);
        it->strings[i] = ip_str(text.ptr, text.len);
    }
    for (uint32_t i = 0; i < module->nglobals; i++) {
        it->globals[i] = ip_default_val(it, module->globals[i].ty, 0);
    }
    mir_interp_register(it, "msrt_fault", ip_host_fault, &it->arena);
    mir_interp_register(it, "msrt_print_int", ip_host_print, NULL);
    mir_interp_register(it, "msrt_print_float", ip_host_print, NULL);
    mir_interp_register(it, "msrt_print_bool", ip_host_print, NULL);
    mir_interp_register(it, "msrt_print_str", ip_host_print, NULL);
    /* The oracle frees at exit, so a leak shows as a drop count that differs. */
    mir_interp_register(it, "msrt_exit_frees", ip_host_true, NULL);
    mir_interp_register(it, "msrt_shield_enter", ip_host_void, NULL);
    mir_interp_register(it, "msrt_shield_exit", ip_host_void, NULL);
    /* The oracle never delivers a cancel. */
    mir_interp_register(it, "msrt_unwinding", ip_host_zero, NULL);
    return it;
}

void mir_interp_free(MirInterp *interp) {
    if (interp == NULL) {
        return;
    }
    for (uint32_t i = 0; i < interp->nstrings; i++) mir_val_release(&interp->strings[i]);
    for (uint32_t i = 0; i < interp->module->nglobals; i++) mir_val_release(&interp->globals[i]);
    for (uint32_t i = 0; i < interp->nmemory; i++) mir_val_release(&interp->memory[i]);
    for (uint32_t i = 0; i < interp->ncleanup; i++) mir_val_release(&interp->cleanup[i].value);
    for (uint32_t i = 0; i < interp->ncall_args; i++) mir_val_release(&interp->call_args[i]);
    free(interp->strings);
    free(interp->globals);
    free(interp->memory);
    free(interp->cleanup);
    free(interp->drop_cache);
    free(interp->hosts);
    free(interp->call_args);
    ms_buf_free(&interp->out);
    ms_arena_free(&interp->arena);
    free(interp);
}

void mir_interp_set_fuel(MirInterp *interp, uint64_t fuel) {
    interp->fuel = fuel;
}

void mir_interp_set_cancel(MirInterp *interp, bool cancelled) {
    interp->cancelled = cancelled;
}

MsStr mir_interp_stdout(const MirInterp *interp) {
    MsStr text = {.ptr = interp->out.data == NULL ? "" : interp->out.data,
                  .len = (uint32_t)interp->out.len};
    return text;
}

uint64_t mir_interp_drops(const MirInterp *interp) {
    return interp->drops;
}

uint64_t mir_interp_steps(const MirInterp *interp) {
    return interp->steps;
}

const MirInterpFault *mir_interp_fault(const MirInterp *interp) {
    return &interp->fault;
}

/* ---- frames ---- */

/* Pushes a frame for `callee`, moving the staged arguments into its entry parameters. */
static IpFlow ip_enter(MirInterp *it, IpFrames *frames, uint32_t callee, MirVal *args,
                       uint32_t nargs, MirValue ret_dst) {
    const MirFunc *func = callee < it->module->nfuncs ? &it->module->funcs[callee] : NULL;
    if (func == NULL || func->nblocks == 0 || nargs != func->nparams) {
        for (uint32_t i = 0; i < nargs; i++) mir_val_release(&args[i]);
        return ip_internal(it, "bad call: wrong function or argument count");
    }
    if (frames->count == frames->capacity) {
        uint32_t grown = ip_grow_cap(frames->capacity, 16);
        frames->frames = ip_regrow(frames->frames, sizeof(IpFrame) * frames->capacity, sizeof(IpFrame) * grown);
        frames->capacity = grown;
    }
    IpFrame *frame = &frames->frames[frames->count++];
    *frame = (IpFrame){.func = callee, .ret_dst = ret_dst};
    frame->regs = calloc((size_t)func->nvalues + 1, sizeof(MirVal));
    if (frame->regs == NULL) ip_oom();
    const MirBlockData *entry = &func->blocks[0];
    for (uint32_t i = 0; i < nargs; i++) {
        if (i < entry->nparams && entry->params[i].value < func->nvalues) {
            frame->regs[entry->params[i].value] = args[i];
            args[i] = ip_void();
        } else {
            mir_val_release(&args[i]);
        }
    }
    return IP_NEXT;
}

static void ip_pop_frame(IpFrames *frames) {
    IpFrame *frame = &frames->frames[--frames->count];
    free(frame->regs);
    frame->regs = NULL;
}

/* The registers of a finished frame hold values: give them up. */
static void ip_drop_registers(const MirModule *module, const IpFrame *frame) {
    const MirFunc *func = &module->funcs[frame->func];
    for (uint32_t i = 0; i < func->nvalues; i++) {
        mir_val_release(&frame->regs[i]);
    }
}

/* Moves the arguments of a branch into the parameters of its target block and jumps there. */
static void ip_jump(MirInterp *it, const MirFunc *func, IpFrame *frame, const MirTarget *target) {
    if (target->block >= func->nblocks) {
        frame->block = UINT32_MAX;
        return;
    }
    const MirBlockData *dest = &func->blocks[target->block];
    uint32_t count = target->nargs < dest->nparams ? target->nargs : dest->nparams;
    MirVal *staged = ip_stage(it, count);
    for (uint32_t i = 0; i < count; i++) {
        staged[i] = ip_take_arg(it, func, frame->regs, target->args[i], dest->params[i].mode == MM_MOVE);
    }
    for (uint32_t i = 0; i < count; i++) {
        MirValue param = dest->params[i].value;
        if (param < func->nvalues) {
            mir_val_release(&frame->regs[param]);
            frame->regs[param] = staged[i];
        } else {
            mir_val_release(&staged[i]);
        }
        staged[i] = ip_void();
    }
    frame->block = target->block;
    frame->ip = 0;
}

static void ip_release_frames(const MirModule *module, IpFrames *frames) {
    while (frames->count > 0) {
        ip_drop_registers(module, &frames->frames[frames->count - 1]);
        ip_pop_frame(frames);
    }
    free(frames->frames);
    *frames = (IpFrames){0};
}

/* ---- running ---- */

static MsStr ip_fault_text(const MirInterp *it, const MirTerm *term, MirFault kind) {
    if (kind == MF_MESSAGE) {
        return ms_name(&it->module->strings, term->fault_str);
    }
    const char *fixed = kind == MF_CALL_DEPTH ? ip_depth_message() : "fault";
    switch (kind) {
    case MF_INT_OVERFLOW: fixed = "integer overflow"; break;
    case MF_DIV_BY_ZERO: fixed = "division by zero"; break;
    case MF_INDEX_OUT_OF_RANGE: fixed = "index out of range"; break;
    case MF_NONE_UNWRAP: fixed = "unwrap of none"; break;
    case MF_CANCELLED: fixed = "cancelled"; break;
    case MF_UNREACHABLE: fixed = "unreachable code reached"; break;
    case MF_CALL_DEPTH: case MF_MESSAGE: break;
    }
    return (MsStr){.ptr = fixed, .len = (uint32_t)strlen(fixed)};
}

static IpFlow ip_return(MirInterp *it, IpFrames *frames, const MirFunc *func, MirVal *result) {
    IpFrame *top = &frames->frames[frames->count - 1];
    MirValue source = func->blocks[top->block].term.value;
    MirVal value = ip_void();
    if (source < func->nvalues) {
        value = top->regs[source];
        top->regs[source] = ip_void();
    }
    MirValue destination = top->ret_dst;
    ip_drop_registers(it->module, top);
    ip_pop_frame(frames);
    if (frames->count == 0) {
        *result = value;
        return IP_DONE;
    }
    IpFrame *caller = &frames->frames[frames->count - 1];
    if (destination < it->module->funcs[caller->func].nvalues) {
        mir_val_release(&caller->regs[destination]);
        caller->regs[destination] = value;
    } else {
        mir_val_release(&value);
    }
    return IP_NEXT;
}

static IpFlow ip_switch(MirInterp *it, const MirFunc *func, IpFrame *frame, const MirTerm *term) {
    const MirVal *scrutinee = term->value < func->nvalues ? &frame->regs[term->value] : NULL;
    const MirTarget *chosen = &term->b;
    for (uint32_t i = 0; scrutinee != NULL && scrutinee->tag == MV_INT && i < term->ncases; i++) {
        if (term->cases[i].value == scrutinee->as.i) {
            chosen = &term->cases[i].target;
            break;
        }
    }
    ip_jump(it, func, frame, chosen);
    return IP_NEXT;
}

static IpFlow ip_terminate(MirInterp *it, IpFrames *frames, const MirFunc *func,
                           const MirBlockData *block, MirVal *result) {
    IpFrame *top = &frames->frames[frames->count - 1];
    const MirTerm *term = &block->term;
    switch ((MirTermKind)term->kind) {
    case MT_RET:
        return ip_return(it, frames, func, result);
    case MT_FAULT:
        return ip_raise_text(it, (MirFault)term->fault, ip_fault_text(it, term, (MirFault)term->fault));
    case MT_UNREACHABLE:
        return ip_raise(it, MF_UNREACHABLE, "unreachable code reached");
    case MT_BR:
        ip_jump(it, func, top, &term->a);
        return IP_NEXT;
    case MT_CONDBR: {
        bool taken = term->value < func->nvalues && top->regs[term->value].tag == MV_BOOL &&
                     top->regs[term->value].as.i != 0;
        ip_jump(it, func, top, taken ? &term->a : &term->b);
        return IP_NEXT;
    }
    case MT_SWITCH:
        return ip_switch(it, func, top, term);
    }
    return ip_internal(it, "unknown terminator");
}

static IpFlow ip_instruct(MirInterp *it, IpFrames *frames, const MirFunc *func,
                          const MirBlockData *block) {
    IpFrame *top = &frames->frames[frames->count - 1];
    const MirInst *inst = &block->insts[top->ip];
    top->ip++;
    IpFlow flow = ip_step(it, func, top->regs, inst);
    if (flow != IP_CALL) {
        return flow;
    }
    if (frames->count >= MIR_INTERP_MAX_FRAMES) {
        for (uint32_t i = 0; i < it->ncall_args; i++) {
            mir_val_release(&it->call_args[i]);
        }
        it->ncall_args = 0;
        return ip_raise(it, MF_CALL_DEPTH, "%s", ip_depth_message());
    }
    return ip_enter(it, frames, it->callee, it->call_args, it->ncall_args, inst->res);
}

/* The main loop: true when the outermost frame returned. */
static bool ip_run(MirInterp *it, IpFrames *frames, MirVal *result) {
    for (;;) {
        if (it->fuel != 0 && it->steps >= it->fuel) {
            (void)ip_raise(it, MF_CANCELLED, "instruction budget exhausted");
            it->raw.fuel = true;
            return false;
        }
        it->steps++;
        if (frames->count == 0) {
            (void)ip_internal(it, "no frame to run");
            return false;
        }
        const IpFrame *top = &frames->frames[frames->count - 1];
        const MirFunc *func = &it->module->funcs[top->func];
        if (top->block >= func->nblocks) {
            (void)ip_internal(it, "jump to an unknown block");
            return false;
        }
        const MirBlockData *block = &func->blocks[top->block];
        IpFlow flow = top->ip < block->ninsts ? ip_instruct(it, frames, func, block)
                                              : ip_terminate(it, frames, func, block, result);
        if (flow == IP_RAISE) {
            return false;
        }
        if (flow == IP_DONE) {
            return true;
        }
    }
}

/* ---- faults ---- */

static MsStr ip_frame_text(MirInterp *it, const IpFrame *frame) {
    const MirModule *module = it->module;
    const MirFunc *func = &module->funcs[frame->func];
    MsStr name = ms_name(&module->names, func->name);
    MirLoc loc = MIR_LOC_NONE;
    if (frame->block < func->nblocks) {
        const MirBlockData *block = &func->blocks[frame->block];
        bool inside = frame->ip > 0 && frame->ip <= block->ninsts;
        loc = inside ? block->insts[frame->ip - 1].loc : block->term_loc;
    }
    if (mir_loc_none(loc)) {
        return ms_arena_fmt(&it->arena, "%.*s", (int)name.len, name.ptr);
    }
    MsStr file = loc.file < module->nfiles ? module->files[loc.file] : (MsStr){"?", 1};
    return ms_arena_fmt(&it->arena, "%.*s (%.*s:%u)", (int)name.len, name.ptr, (int)file.len,
                        file.ptr, loc.line);
}

/* Runs the pending cleanup actions, last in first out; the messages of the ones that fault. */
static uint32_t ip_run_cleanups(MirInterp *it, MsStr **messages) {
    uint32_t count = 0, capacity = 0;
    *messages = NULL;
    if (it->unwinding) {
        return 0;
    }
    it->unwinding = true;
    while (it->ncleanup > 0) {
        IpCleanup action = it->cleanup[--it->ncleanup];
        MirVal result = ip_void();
        if (ip_exec(it, action.closer, &action.value, 1, &result)) {
            mir_val_release(&result);
            continue;
        }
        if (count == capacity) {
            capacity = ip_grow_cap(capacity, 4);
            MsStr *grown = MS_NEW_N(&it->arena, MsStr, capacity);
            if (count > 0) memcpy(grown, *messages, sizeof(MsStr) * count);
            *messages = grown;
        }
        (*messages)[count++] = it->fault.message;
    }
    it->unwinding = false;
    return count;
}

/* Builds the final fault from `it->raw`: the frames, then the cleanup actions, then the frames go. */
static void ip_finish(MirInterp *it, IpFrames *frames) {
    IpRaw raw = it->raw;
    MsStr *stack = MS_NEW_N(&it->arena, MsStr, (size_t)frames->count + 1);
    for (uint32_t i = 0; i < frames->count; i++) {
        stack[i] = ip_frame_text(it, &frames->frames[frames->count - 1 - i]);
    }
    uint32_t nstack = frames->count;
    MsStr *cleanup_messages = NULL;
    uint32_t ncleanup = ip_run_cleanups(it, &cleanup_messages);
    it->depth = 0;
    it->fault = (MirInterpFault){.kind = raw.kind, .message = raw.message, .stack = stack,
                                 .nstack = nstack, .cleanup_faults = cleanup_messages,
                                 .ncleanup_faults = ncleanup, .fuel_exhausted = raw.fuel};
    ip_release_frames(it->module, frames);
}

bool ip_exec(MirInterp *it, uint32_t entry, MirVal *args, uint32_t nargs, MirVal *result) {
    IpFrames frames = {0};
    if (it->exec_depth >= IP_MAX_EXEC_DEPTH) {
        for (uint32_t i = 0; i < nargs; i++) mir_val_release(&args[i]);
        (void)ip_internal(it, "cleanup actions nest too deeply");
        ip_finish(it, &frames);
        return false;
    }
    it->exec_depth++;
    bool ok = ip_enter(it, &frames, entry, args, nargs, MIR_NONE) == IP_NEXT &&
              ip_run(it, &frames, result);
    if (ok) {
        ip_release_frames(it->module, &frames);
    } else {
        ip_finish(it, &frames);
    }
    it->exec_depth--;
    return ok;
}

/* ---- entry points ---- */

static bool ip_plain_fault(MirInterp *it, const char *text) {
    it->fault = (MirInterpFault){.kind = MF_UNREACHABLE,
                                 .message = ms_arena_fmt(&it->arena, "%s", text)};
    return false;
}

bool mir_interp_call(MirInterp *interp, uint32_t func, MirVal *args, uint32_t nargs, MirVal *result) {
    interp->unwinding = false;
    return ip_exec(interp, func, args, nargs, result);
}

bool mir_interp_run_entry(MirInterp *interp, int64_t *exit_code) {
    if (interp->module->entry == MIR_NONE) {
        return ip_plain_fault(interp, "module has no entry");
    }
    MirVal result = ip_void();
    if (!mir_interp_call(interp, interp->module->entry, NULL, 0, &result)) {
        return false;
    }
    if (result.tag != MV_INT) {
        mir_val_release(&result);
        return ip_plain_fault(interp, "entry returned something other than an int");
    }
    *exit_code = result.as.i;
    return true;
}
