/* Wait groups. See group.h. */
#include "group.h"

#include "array.h"
#include "ms_rt/alloc.h"
#include "scheduler.h"

typedef struct Group {
    uint32_t *done; /* ring of finished tags, oldest first */
    size_t done_head;
    size_t done_length;
    size_t done_capacity;
    size_t pending;   /* members that have not finished */
    uint64_t token;   /* the waiter's token while it is parked in ms_group_next, or 0 */
    uint64_t interrupt; /* the token of the park of a watched inline run, or 0 */
    MsPromise *members; /* the promises added, to detach them when the group is freed */
    size_t member_count;
    size_t member_capacity;
    uint8_t joined;
    bool failed; /* a member ended without a value and the inline run was not told yet */
    bool live;
} Group;

/* Which group a promise row reports to, keyed by the row of its id: the stored id guards against a reused row. */
typedef struct Member {
    MsPromise id;
    uint32_t group;
    uint32_t tag;
} Member;

typedef struct Groups {
    Group *items;
    size_t count;
    size_t capacity;
    uint32_t *free_ids;
    size_t free_count;
    size_t free_capacity;
    Member *members;
    size_t member_rows;
    size_t member_row_capacity;
} Groups;

static _Thread_local Groups groups; /* per-thread state, like the scheduler's */

/* What an inline run reports failures to. Lives on the stack of ms_promise_run_watched. */
typedef struct Watch {
    int64_t group;
    const MsPromise *ids;
    size_t count;
    size_t from;
    bool parked;
    bool interrupted;
} Watch;

static void fail(const char *text) { ms_sched()->hooks.fault(MS_FAULT_KIND_FAULT, text); }

static Group *group_of(int64_t id) {
    if (id <= 0 || (size_t)id > groups.count || !groups.items[id - 1].live) {
        fail("promise: no such wait group");
    }
    return &groups.items[id - 1];
}

int64_t ms_group_new(void) {
    size_t index = 0;
    if (groups.free_count != 0) {
        index = groups.free_ids[--groups.free_count];
    } else {
        void *items = groups.items;
        if (!ms_array_reserve(&items, &groups.capacity, groups.count + 1, sizeof *groups.items)) {
            fail("promise: out of memory");
        }
        groups.items = items;
        index = groups.count++;
        groups.items[index] = (Group){0}; /* a grown array is not zeroed: a fresh slot owns no buffers yet */
    }
    groups.items[index] = (Group){.live = true, .done = groups.items[index].done,
                                  .done_capacity = groups.items[index].done_capacity,
                                  .members = groups.items[index].members,
                                  .member_capacity = groups.items[index].member_capacity};
    return (int64_t)index + 1;
}

static void push_done(Group *group, uint32_t tag) {
    if (group->done_length == group->done_capacity) {
        /* Grow the ring and straighten it. */
        const size_t capacity = group->done_capacity == 0 ? 8 : group->done_capacity * 2;
        uint32_t *const done = msrt_alloc(capacity * sizeof *done);
        for (size_t i = 0; i < group->done_length; i++) {
            done[i] = group->done[(group->done_head + i) % group->done_capacity];
        }
        msrt_free(group->done);
        group->done = done;
        group->done_capacity = capacity;
        group->done_head = 0;
    }
    group->done[(group->done_head + group->done_length++) % group->done_capacity] = tag;
}

static bool pop_done(Group *group, uint32_t *tag) {
    if (group->done_length == 0) {
        return false;
    }
    *tag = group->done[group->done_head];
    group->done_head = (group->done_head + 1) % group->done_capacity;
    group->done_length--;
    return true;
}

static Member *member_row(MsPromise id) {
    const size_t row = (size_t)((uint64_t)id & 0xffffffffu) - 1;
    if (row >= groups.member_rows) {
        void *rows = groups.members;
        const size_t before = groups.member_row_capacity;
        if (!ms_array_reserve(&rows, &groups.member_row_capacity, row + 1, sizeof *groups.members)) {
            fail("promise: out of memory");
        }
        groups.members = rows;
        for (size_t i = before; i < groups.member_row_capacity; i++) {
            groups.members[i] = (Member){0};
        }
        groups.member_rows = row + 1;
    }
    return &groups.members[row];
}

bool ms_group_add(int64_t group_id, MsPromise id, int64_t tag) {
    Group *const group = group_of(group_id);
    const MsPromiseProbe probe = ms_promise_probe(id);
    if (probe == MS_PROMISE_GONE) {
        push_done(group, (uint32_t)tag);
        return true;
    }
    if (probe != MS_PROMISE_PENDING) {
        group->failed = group->failed || probe == MS_PROMISE_FAILED_PROBE;
        push_done(group, (uint32_t)tag);
        return true;
    }
    Member *const member = member_row(id);
    if (member->id == id && member->group != 0) {
        return false;
    }
    if (group->member_count == group->member_capacity) {
        void *members = group->members;
        if (!ms_array_reserve(&members, &group->member_capacity, group->member_count + 1, sizeof *group->members)) {
            fail("promise: out of memory");
        }
        group->members = members;
    }
    group->members[group->member_count++] = id;
    *member = (Member){.id = id, .group = (uint32_t)group_id, .tag = (uint32_t)tag};
    ms_promise_set_grouped(id, true);
    group->pending++;
    return true;
}

int64_t ms_group_join(int64_t group_id, const MsPromise *ids, size_t count, size_t from) {
    Group *group = group_of(group_id);
    if (group->joined != 0) {
        return group->joined;
    }
    uint8_t mode = MS_GROUP_JOINED_ALL;
    for (size_t at = from; at < count; at++) {
        if (!ms_group_add(group_id, ids[at], (int64_t)at)) {
            mode = MS_GROUP_JOINED_PARTLY;
        }
    }
    group = group_of(group_id);
    group->joined = mode;
    return mode;
}

void ms_group_finished(MsPromise id, bool failed) {
    Member *const member = member_row(id);
    if (member->id != id || member->group == 0) {
        return;
    }
    Group *const group = &groups.items[member->group - 1];
    push_done(group, member->tag);
    member->group = 0;
    group->pending--;
    if (failed) {
        group->failed = true;
        /* The waiter is parked inside a promise it runs inline: end that run, so the failure is reported without
         * waiting for the promise to finish. */
        const uint64_t interrupt = group->interrupt;
        group->interrupt = 0;
        if (interrupt != 0) {
            ms_token_post(interrupt, 0);
        }
    }
    const uint64_t token = group->token;
    group->token = 0;
    if (token != 0) {
        ms_token_post(token, 1);
    }
}

/* Whether a member still pending may be finished by another thread or isolate. */
static bool members_elsewhere(const Group *group) {
    for (size_t i = 0; i < group->member_count; i++) {
        if (ms_promise_completes_elsewhere(group->members[i])) {
            return true;
        }
    }
    return false;
}

int64_t ms_group_next(int64_t group_id) {
    for (;;) {
        Group *const group = group_of(group_id);
        uint32_t tag = 0;
        if (pop_done(group, &tag)) {
            return tag;
        }
        if (group->pending == 0) {
            return -1;
        }
        const uint64_t token = ms_token_new(members_elsewhere(group) ? MS_TOKEN_REMOTE : 0);
        if (token == 0) {
            fail("promise: out of wait tokens");
        }
        group->token = token;
        uint64_t value = 0;
        uint32_t result = 0;
        (void)ms_token_park(token, -1, &value, &result);
        group_of(group_id)->token = 0;
        (void)ms_token_free(token);
        if (result == MS_WAIT_CANCELLED) {
            ms_cancelled();
        }
    }
}

int64_t ms_group_poll(int64_t group_id) {
    uint32_t tag = 0;
    return pop_done(group_of(group_id), &tag) ? (int64_t)tag : -1;
}

void ms_group_free(int64_t group_id) {
    Group *const group = group_of(group_id);
    for (size_t i = 0; i < group->member_count; i++) {
        Member *const member = member_row(group->members[i]);
        if (member->id == group->members[i] && member->group == (uint32_t)group_id) {
            member->group = 0;
            ms_promise_set_grouped(group->members[i], false);
        }
    }
    group->member_count = 0;
    group->done_length = 0;
    group->done_head = 0;
    group->pending = 0;
    group->token = 0;
    group->interrupt = 0;
    group->failed = false;
    group->joined = 0;
    group->live = false;
    if (groups.free_count == groups.free_capacity) {
        void *ids = groups.free_ids;
        if (!ms_array_reserve(&ids, &groups.free_capacity, groups.free_count + 1, sizeof *groups.free_ids)) {
            return;
        }
        groups.free_ids = ids;
    }
    groups.free_ids[groups.free_count++] = (uint32_t)(group_id - 1);
}

/* ---- inline runs ---- */

static bool park_begin(uint64_t token) {
    Watch *const watch = ms_task_watch();
    if (!watch->parked) {
        watch->parked = true;
        (void)ms_group_join(watch->group, watch->ids, watch->count, watch->from);
    }
    Group *const group = group_of(watch->group);
    if (group->failed) {
        group->failed = false;
        watch->interrupted = true;
        return true;
    }
    group->interrupt = token;
    return false;
}

static bool park_end(void) {
    Watch *const watch = ms_task_watch();
    Group *const group = group_of(watch->group);
    group->interrupt = 0;
    watch->interrupted = group->failed;
    group->failed = false;
    return watch->interrupted;
}

int64_t ms_promise_run_watched(MsPromise id, int64_t group, const MsPromise *ids, size_t count, size_t from) {
    Watch watch = {.group = group, .ids = ids, .count = count, .from = from};
    void *const before = ms_task_set_watch(&watch);
    const bool ran = ms_promise_run_inline(id);
    (void)ms_task_set_watch(before);
    if (watch.interrupted) {
        return MS_RUN_INTERRUPTED;
    }
    return ran ? MS_RUN_RAN : MS_RUN_NOTHING;
}

void ms_group_hooks(MsSchedHooks *hooks) {
    hooks->park_begin = park_begin;
    hooks->park_end = park_end;
}

void ms_groups_teardown(void) {
    for (size_t i = 0; i < groups.count; i++) {
        msrt_free(groups.items[i].done);
        msrt_free(groups.items[i].members);
    }
    msrt_free(groups.items);
    msrt_free(groups.free_ids);
    msrt_free(groups.members);
    groups = (Groups){0};
}
