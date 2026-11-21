/* Runs every function of a module whose parameters are all `Int`, `Bool` or `Float` over a fixed
 * set of arguments and prints `file function(args) = result`, one line per call, for the lowering
 * differential: two modules that compute the same function print the same lines. For the dump
 * tools of compiler/tools; include it from one file. */
#ifndef MS_TOOLS_MIR_RUN_H
#define MS_TOOLS_MIR_RUN_H

#include <stdio.h>

#include "ms/mir_interp.h"

enum { RUN_CALLS = 24, RUN_FUEL = 100000 };

static const int64_t run_ints[] = {0, 1, -1, 3, 2, -7, 100, 5};
static const double run_floats[] = {0.0, 1.5, -2.0, 0.25};

static bool run_params_are_scalar(const MirFunc *f) {
    for (uint32_t i = 0; i < f->nparams; i++) {
        const MirTy ty = f->params[i].ty;
        if (ty != MIR_INT && ty != MIR_BOOL && ty != MIR_FLOAT) {
            return false;
        }
    }
    return true;
}

/* The argument `param` takes in call number `call`: the calls walk each parameter's samples at
 * different strides so the combinations differ. */
static MirVal run_argument(MirTy ty, uint32_t param, uint32_t call) {
    const uint32_t pick = call * (param + 1) + param;
    if (ty == MIR_BOOL) {
        return mir_val_bool((pick & 1) != 0);
    }
    if (ty == MIR_FLOAT) {
        return (MirVal){.tag = MV_FLOAT, .as.f = run_floats[pick % (sizeof run_floats / sizeof *run_floats)]};
    }
    return mir_val_int(run_ints[pick % (sizeof run_ints / sizeof *run_ints)]);
}

static void run_print_value(const MirVal *v) {
    switch ((MirValTag)v->tag) {
    case MV_INT: printf("%lld", (long long)v->as.i); break;
    case MV_BOOL: fputs(v->as.i != 0 ? "true" : "false", stdout); break;
    case MV_FLOAT: printf("%.17g", v->as.f); break;
    case MV_VOID:
    case MV_STR:
    case MV_PTR:
    case MV_TYPE:
    case MV_ALT:
    case MV_LIST:
    case MV_OPT:
    case MV_MAP:
    case MV_CLOSURE:
    case MV_IFACE: fputs("?", stdout); break;
    }
}

static void run_one_call(MirInterp *interp, const MirModule *m, uint32_t id, const char *file, uint32_t call) {
    const MirFunc *f = &m->funcs[id];
    const MsStr name = ms_name(&m->names, f->name);
    MirVal args[16];
    printf("%s %.*s(", file, (int)name.len, name.ptr);
    for (uint32_t p = 0; p < f->nparams; p++) {
        args[p] = run_argument(f->params[p].ty, p, call);
        printf(p == 0 ? "" : ", ");
        run_print_value(&args[p]);
    }
    MirVal result = {0};
    const bool ok = mir_interp_call(interp, id, args, f->nparams, &result);
    fputs(") = ", stdout);
    if (ok) {
        run_print_value(&result);
        mir_val_release(&result);
    } else {
        const MirInterpFault *fault = mir_interp_fault(interp);
        printf(fault->fuel_exhausted ? "fuel" : "fault %d", (int)fault->kind);
    }
    putchar('\n');
}

/* Calls every scalar function of `m` RUN_CALLS times, each call on a fresh interpreter: a call that
 * runs out of fuel leaves its frames behind. */
static void run_module(const MirModule *m, const char *file) {
    for (uint32_t id = 0; id < m->nfuncs; id++) {
        const MirFunc *f = &m->funcs[id];
        if (f->nparams > 16 || !run_params_are_scalar(f) || f->name == MIR_NONE) {
            continue;
        }
        for (uint32_t call = 0; call < RUN_CALLS; call++) {
            MirInterp *interp = mir_interp_new(m);
            mir_interp_set_fuel(interp, RUN_FUEL);
            run_one_call(interp, m, id, file, call);
            mir_interp_free(interp);
        }
    }
}

#endif
