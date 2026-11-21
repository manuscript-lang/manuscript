/* Wait groups. See group.h. */
#include "runtime/core/group.h"

#include "base/alloc.h"
#include "runtime/core/scheduler.h"

typedef struct Group {
  uint32_t *done; /* ring of finished tags, oldest first */
  size_t done_head;
  size_t done_length;
  size_t done_capacity;
  size_t pending;   /* members that have not finished */
  uint64_t token;   /* the waiter's token while it is parked in ms_group_next, or 0 */
  uint64_t interrupt; /* the token of the park of a watched inline run, or 0 */
  MsPromiseList members; /* the promises added, to detach them when the group is freed */
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

MS_LIST_DEFINE(GroupList, group_list, Group)
MS_LIST_DEFINE(MemberList, member_list, Member)
MS_LIST_DEFINE(IdList, id_list, uint32_t)

typedef struct Groups {
  GroupList items;
  IdList free_ids;
  MemberList members; /* by promise row */
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

static void fail(const char *text) { ms_fault_text(MS_FAULT_KIND_FAULT, text); }

static Group *group_of(int64_t id) {
  if (id <= 0 || (size_t)id > groups.items.len || !groups.items.ptr[id - 1].live) {
    fail("promise: no such wait group");
  }
  return &groups.items.ptr[id - 1];
}

int64_t ms_group_new(void) {
  size_t index = 0;
  if (groups.free_ids.len != 0) {
    index = groups.free_ids.ptr[--groups.free_ids.len];
  } else {
    index = groups.items.len;
    group_list_push(&groups.items, (Group){0});
  }
  /* A reused slot keeps the buffers it grew. */
  Group *const fresh = &groups.items.ptr[index];
  *fresh = (Group){.live = true, .done = fresh->done, .done_capacity = fresh->done_capacity, .members = fresh->members};
  fresh->members.len = 0;
  return (int64_t)index + 1;
}

static void push_done(Group *group, uint32_t tag) {
  if (group->done_length == group->done_capacity) {
    /* Grow the ring and straighten it. */
    const size_t capacity = group->done_capacity == 0 ? 8 : group->done_capacity * 2;
    uint32_t *const done = ms_alloc(capacity * sizeof *done);
    for (size_t i = 0; i < group->done_length; i++) {
      done[i] = group->done[(group->done_head + i) % group->done_capacity];
    }
    ms_free(group->done);
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
  while (row >= groups.members.len) {
    member_list_push(&groups.members, (Member){0});
  }
  return &groups.members.ptr[row];
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
  /* A foreign promise finishes in its owner's group table, not this one: the caller polls it with wait_any. */
  if (ms_promise_is_foreign(id)) {
    return false;
  }
  Member *const member = member_row(id);
  if (member->id == id && member->group != 0) {
    return false;
  }
  ms_promise_list_push(&group->members, id);
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
  Group *const group = &groups.items.ptr[member->group - 1];
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
  for (size_t i = 0; i < group->members.len; i++) {
    if (ms_promise_completes_elsewhere(group->members.ptr[i])) {
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
  for (size_t i = 0; i < group->members.len; i++) {
    Member *const member = member_row(group->members.ptr[i]);
    if (member->id == group->members.ptr[i] && member->group == (uint32_t)group_id) {
      member->group = 0;
      ms_promise_set_grouped(group->members.ptr[i], false);
    }
  }
  group->members.len = 0;
  group->done_length = 0;
  group->done_head = 0;
  group->pending = 0;
  group->token = 0;
  group->interrupt = 0;
  group->failed = false;
  group->joined = 0;
  group->live = false;
  id_list_push(&groups.free_ids, (uint32_t)(group_id - 1));
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
  for (size_t i = 0; i < groups.items.len; i++) {
    ms_free(groups.items.ptr[i].done);
    ms_promise_list_free(&groups.items.ptr[i].members);
  }
  group_list_free(&groups.items);
  id_list_free(&groups.free_ids);
  member_list_free(&groups.members);
  groups = (Groups){0};
}
