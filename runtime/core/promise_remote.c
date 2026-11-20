/* Promise calls across isolates. See promise_remote.h. */
#include "promise_remote.h"

#include <string.h>

#include "isolate.h"
#include "ms_rt/alloc.h"
#include "scheduler.h"

typedef enum AskOp {
    ASK_DONE = 1,
    ASK_OUTCOME,
    ASK_TAKE,
    ASK_CANCEL,
    ASK_LIMIT,
    ASK_END,
    ASK_DROP,
    ASK_REPORT,
    ASK_PROBE,
    ASK_ON_CANCEL,
    ASK_GROUPED,
    ASK_RUN,
    ASK_DRAIN,
} AskOp;

/* One question. The asker owns it and keeps it alive until the reply token is posted. */
typedef struct Ask {
    MsPromise id;
    AskOp op;
    int64_t argument;
    int64_t extra; /* a second argument: the grace of ASK_DRAIN */
    const MsTypeDesc *desc;
    uint8_t *out;
    int64_t answer;
    MsFaultText text;
    uint64_t token;
} Ask;

/* ---- the asker ---- */

static void shielded_park(uint64_t token) {
    uint64_t value = 0;
    uint32_t result = 0;
    ms_shield_enter();
    while (ms_token_park(token, -1, &value, &result) == MS_TOKEN_OK && result != 0) {
        /* an early wake (a stray cancel): the reply has not come yet */
    }
    ms_shield_exit();
}

/* Sends `ask` to the owner of its promise and waits for the answer; false when the owner is gone. */
static bool ask_owner(Ask *ask) {
    const uint32_t owner = (uint32_t)((uint64_t)ask->id >> 56);
    ask->token = ms_token_new(MS_TOKEN_REMOTE);
    if (ask->token == 0) {
        return false;
    }
    MsMail *const mail = msrt_alloc(sizeof *mail);
    *mail = (MsMail){.kind = MS_MAIL_PROMISE, .a = MS_MAIL_ASK, .b = (uint64_t)ask->id, .p = ask};
    if (!ms_isolate_post(owner, mail)) {
        msrt_free(mail);
        (void)ms_token_free(ask->token);
        return false;
    }
    shielded_park(ask->token);
    (void)ms_token_free(ask->token);
    return true;
}

static int64_t simple(MsPromise id, AskOp op, int64_t argument, int64_t gone) {
    Ask ask = {.id = id, .op = op, .argument = argument, .answer = gone};
    return ask_owner(&ask) ? ask.answer : gone;
}

bool ms_remote_done(MsPromise id) { return simple(id, ASK_DONE, 0, 1) != 0; }

void ms_remote_cancel(MsPromise id) { (void)simple(id, ASK_CANCEL, 0, 0); }

void ms_remote_limit(MsPromise id, int64_t timeout_ns) { (void)simple(id, ASK_LIMIT, timeout_ns, 0); }

bool ms_remote_end(MsPromise id) { return simple(id, ASK_END, 0, 0) != 0; }

void ms_remote_drop(MsPromise id) { (void)simple(id, ASK_DROP, 0, 0); }

MsPromiseProbe ms_remote_probe(MsPromise id) { return (MsPromiseProbe)simple(id, ASK_PROBE, 0, MS_PROMISE_GONE); }

void ms_remote_on_cancel(MsPromise id, int64_t cancel) { (void)simple(id, ASK_ON_CANCEL, cancel, 0); }

void ms_remote_set_grouped(MsPromise id, bool grouped) { (void)simple(id, ASK_GROUPED, grouped ? 1 : 0, 0); }

bool ms_remote_run_inline(MsPromise id) { return simple(id, ASK_RUN, 0, 0) != 0; }

void ms_remote_drain(MsPromise id, int64_t drain, int64_t grace_ns) {
    Ask ask = {.id = id, .op = ASK_DRAIN, .argument = drain, .extra = grace_ns};
    (void)ask_owner(&ask);
}

bool ms_remote_watch_post(MsPromise id, uint64_t token) {
    MsMail *const mail = msrt_alloc(sizeof *mail);
    *mail = (MsMail){.kind = MS_MAIL_PROMISE, .a = MS_MAIL_WATCH, .b = (uint64_t)id, .c = token};
    if (!ms_isolate_post((uint32_t)((uint64_t)id >> 56), mail)) {
        msrt_free(mail);
        return false;
    }
    return true;
}

bool ms_remote_take(MsPromise id, const MsTypeDesc *desc, uint8_t *out) {
    Ask ask = {.id = id, .op = ASK_TAKE, .desc = desc, .out = out};
    return ask_owner(&ask) && ask.answer != 0;
}

MsFaultText ms_remote_fault_report(MsPromise id) {
    Ask ask = {.id = id, .op = ASK_REPORT};
    if (!ask_owner(&ask)) {
        return (MsFaultText){0};
    }
    return ask.text;
}

/* Waits by watching: the owner posts a token when the promise finishes, so the wait ends at once on a timeout or a
 * cancel, and a late post finds the token gone. */
int64_t ms_remote_wait(MsPromise id, int64_t timeout_ns) {
    const int64_t deadline = timeout_ns >= 0 ? ms_sched_now() + timeout_ns : -1;
    for (;;) {
        const int64_t code = simple(id, ASK_OUTCOME, 0, MS_PROMISE_CLOSED);
        if (code >= 0) {
            return code;
        }
        const uint64_t token = ms_token_new(MS_TOKEN_REMOTE);
        if (token == 0 || !ms_remote_watch_post(id, token)) {
            (void)ms_token_free(token);
            return MS_PROMISE_CLOSED;
        }
        uint64_t value = 0;
        uint32_t result = 0;
        const MsTokenStatus status = ms_token_park_at(token, deadline, &value, &result);
        (void)ms_token_free(token);
        if (status == MS_TOKEN_OK && result == MS_WAIT_CANCELLED) {
            (void)ms_remote_end(id);
            ms_cancelled();
        }
        if (status == MS_TOKEN_OK && result == MS_WAIT_TIMEOUT) {
            ms_remote_cancel(id);
            return MS_PROMISE_TIMEOUT;
        }
    }
}

/* ---- the owner ---- */

static void answer(Ask *ask) {
    switch (ask->op) {
    case ASK_DONE:
        ask->answer = ms_promise_done(ask->id) ? 1 : 0;
        break;
    case ASK_OUTCOME:
        ask->answer = ms_promise_outcome(ask->id);
        break;
    case ASK_TAKE:
        ask->answer = ms_promise_take(ask->id, ask->desc, ask->out) ? 1 : 0;
        break;
    case ASK_CANCEL:
        ms_promise_cancel(ask->id);
        break;
    case ASK_LIMIT:
        ms_promise_limit(ask->id, ask->argument);
        break;
    case ASK_END:
        ask->answer = ms_promise_end(ask->id) ? 1 : 0;
        break;
    case ASK_DROP:
        ms_promise_drop(ask->id);
        break;
    case ASK_REPORT:
        ask->text = ms_promise_fault_report(ask->id);
        break;
    case ASK_PROBE:
        ask->answer = (int64_t)ms_promise_probe(ask->id);
        break;
    case ASK_ON_CANCEL:
        ms_promise_on_cancel(ask->id, ask->argument);
        break;
    case ASK_GROUPED:
        ms_promise_set_grouped(ask->id, ask->argument != 0);
        break;
    case ASK_RUN:
        ask->answer = ms_promise_run_inline(ask->id) ? 1 : 0;
        break;
    case ASK_DRAIN:
        ms_promise_drain(ask->id, ask->argument, ask->extra);
        break;
    }
}

static void serve_entry(void *argument) {
    Ask *const ask = argument;
    const uint64_t token = ask->token;
    answer(ask);
    ms_token_post_remote(token, 0); /* the asker owns `ask` and frees it after this */
}

void ms_remote_serve(MsMail *mail) {
    Ask *const ask = mail->p;
    msrt_free(mail);
    MsTaskStatus status = MS_TASK_OK;
    if (ms_task_spawn(serve_entry, ask, MS_SPAWN_DETACHED, 0, &status) == 0) {
        ms_token_post_remote(ask->token, 0); /* no stack: answer with the defaults the asker preset */
    }
}

void ms_remote_watch(MsMail *mail) {
    ms_promise_watch((MsPromise)mail->b, mail->c);
    msrt_free(mail);
}
