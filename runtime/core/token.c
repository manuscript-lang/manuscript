/* Tokens: one-shot slots a task parks on and code posts to. See task.h.
 *
 * A token id is `isolate << 52 | generation << 32 | (index + 1)`. The generation is 20 bits; a slot whose
 * generation is used up is retired instead of wrapping back to an id a stale holder might still have.
 */
#include "array.h"
#include "scheduler.h"
#include "sweep.h"

static MsToken *token_find(const MsSched *sched, uint64_t id) {
    const size_t index = (size_t)(id & 0xffffffffu);
    if (index == 0 || index > sched->token_count) {
        return NULL;
    }
    MsToken *const token = &sched->tokens[index - 1];
    const bool current = token->live && token->generation == ((id >> 32) & MS_TOKEN_GENERATION_MASK) &&
                         (id >> MS_TOKEN_ISOLATE_SHIFT) == sched->isolate;
    return current ? token : NULL;
}

bool ms_token_is_remote(const MsSched *sched, uint64_t id) {
    const MsToken *const token = token_find(sched, id);
    return token != NULL && token->remote;
}

/* Ends the token wait a task leaves when its park is abandoned or ends. */
void ms_token_abandon(MsSched *sched, MsTask *task) {
    if (task->wait_token == 0) {
        return;
    }
    MsToken *const token = token_find(sched, task->wait_token);
    if (token != NULL) {
        token->waiter = 0;
    }
    task->wait_token = 0;
}

/* The slot for a new token: a free one, else a new one. NULL when a table size overflows. */
static MsToken *take_token(MsSched *sched, size_t *index) {
    if (sched->free_token_count > 0) {
        *index = sched->free_tokens[--sched->free_token_count];
        return &sched->tokens[*index];
    }
    void *tokens = sched->tokens;
    if (!ms_array_reserve(&tokens, &sched->token_capacity, sched->token_count + 1, sizeof *sched->tokens)) {
        return NULL;
    }
    sched->tokens = tokens;
    *index = sched->token_count++;
    sched->tokens[*index] = (MsToken){0};
    return &sched->tokens[*index];
}

uint64_t ms_token_new(uint32_t flags) {
    MsSched *const sched = ms_sched();
    (void)ms_task_running();
    size_t index = 0;
    MsToken *const token = take_token(sched, &index);
    if (token == NULL) {
        return 0;
    }
    const bool remote = (flags & MS_TOKEN_REMOTE) != 0;
    const bool peer = remote && (flags & MS_TOKEN_PEER) != 0;
    token->generation++;
    token->live = true;
    token->remote = remote;
    token->peer = peer;
    token->waiter = 0;
    token->has_post = false;
    if (remote) {
        sched->remote_tokens++;
        sched->peer_tokens += peer ? 1 : 0;
    }
    return (uint64_t)sched->isolate << MS_TOKEN_ISOLATE_SHIFT | (uint64_t)token->generation << 32 |
           (uint64_t)(index + 1);
}

/* Takes a delivered post, if any: false when the token has none. */
static bool take_post(MsToken *token, uint64_t *value) {
    if (!token->has_post) {
        return false;
    }
    if (value != NULL) {
        *value = token->value;
    }
    token->has_post = false;
    return true;
}

MsTokenStatus ms_token_park_at(uint64_t id, int64_t at_ns, uint64_t *value, uint32_t *result) {
    MsSched *const sched = ms_sched();
    MsTask *const task = ms_task_running();
    MsToken *token = token_find(sched, id);
    if (token == NULL) {
        return MS_TOKEN_NO_SUCH_TOKEN;
    }
    *result = 0;
    if (take_post(token, value)) {
        return MS_TOKEN_OK;
    }
    if (ms_cancel_flag() != 0 || ms_sweep_cancel_here()) {
        *result = MS_WAIT_CANCELLED;
        return MS_TOKEN_OK;
    }
    if (token->waiter != 0) {
        return MS_TOKEN_BUSY;
    }
    /* A shielded cleanup is not cancelled, so a failure elsewhere does not end it either. */
    const bool watched = task->watch != NULL && !ms_task_shielded(task) && sched->hooks.park_begin != NULL;
    if (watched && sched->hooks.park_begin(id)) {
        (void)sched->hooks.park_end();
        *result = MS_WAIT_CANCELLED;
        return MS_TOKEN_OK;
    }
    token->waiter = task->handle;
    task->wait_token = id;
    task->wait_events = 0;
    ms_park_set_deadline(sched, task, at_ns);
    task->state = MS_STATE_WAITING;
    ms_task_switch_away(sched);
    *result = task->wait_result;
    /* The table may have grown while parked: look the token up again. */
    token = token_find(sched, id);
    if (*result == 0 && (token == NULL || !take_post(token, value))) {
        return MS_TOKEN_NO_SUCH_TOKEN;
    }
    if (watched && sched->hooks.park_end()) {
        *result = MS_WAIT_CANCELLED;
    }
    return MS_TOKEN_OK;
}

static int64_t token_deadline(int64_t timeout_ns) {
    if (timeout_ns < 0) {
        return MS_NO_DEADLINE;
    }
    const int64_t now = ms_sched_now();
    return now > INT64_MAX - timeout_ns ? INT64_MAX : now + timeout_ns;
}

MsTokenStatus ms_token_park(uint64_t id, int64_t timeout_ns, uint64_t *value, uint32_t *result) {
    return ms_token_park_at(id, token_deadline(timeout_ns), value, result);
}

void ms_token_post(uint64_t id, uint64_t value) {
    MsSched *const sched = ms_sched();
    (void)ms_task_running();
    MsToken *const token = token_find(sched, id);
    if (token == NULL || token->has_post) {
        return;
    }
    token->has_post = true;
    token->value = value;
    if (token->waiter != 0) {
        MsTask *const waiter = ms_task_lookup(sched, token->waiter);
        if (waiter != NULL) {
            ms_park_wake(sched, waiter, 0);
        }
    }
}

MsTokenStatus ms_token_free(uint64_t id) {
    MsSched *const sched = ms_sched();
    (void)ms_task_running();
    MsToken *const token = token_find(sched, id);
    if (token == NULL) {
        return MS_TOKEN_OK;
    }
    if (token->waiter != 0) {
        return MS_TOKEN_WAITED_ON;
    }
    token->live = false;
    token->has_post = false;
    if (token->remote) {
        sched->remote_tokens--;
        sched->peer_tokens -= token->peer ? 1 : 0;
    }
    token->remote = false;
    token->peer = false;
    /* Retire an exhausted slot instead of wrapping back to a still-stale id. */
    if (token->generation < MS_TOKEN_GENERATION_MASK) {
        void *free_tokens = sched->free_tokens;
        if (ms_array_reserve(&free_tokens, &sched->free_token_capacity, sched->free_token_count + 1,
                             sizeof *sched->free_tokens)) {
            sched->free_tokens = free_tokens;
            sched->free_tokens[sched->free_token_count++] = (uint32_t)((id & 0xffffffffu) - 1);
        }
    }
    return MS_TOKEN_OK;
}

void ms_token_free_all(MsSched *sched) {
    msrt_free(sched->tokens);
    msrt_free(sched->free_tokens);
}
