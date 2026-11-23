/* Owns review.h: port of crates/ms-tooling/src/review.rs. */
#include "tooling/review.h"

#include "base/sort.h"
#include "base/message.h"

const char *const MS_TIER_CONTRACT = "CONTRACT";
const char *const MS_TIER_EFFECT = "EFFECT+";
const char *const MS_TIER_ERROR = "ERROR";
const char *const MS_TIER_RESOURCE = "RESOURCE";
const char *const MS_TIER_INTERNAL = "INTERNAL";

static MsSpan text(const char *literal) {
  return ms_span_of_text(literal);
}

static size_t tier_rank(MsSpan tier) {
  const char *const tiers[] = {"CONTRACT", "EFFECT+", "ERROR", "RESOURCE", "INTERNAL"};
  for (size_t i = 0; i < 5; i++) {
    if (ms_span_is_text(tier, tiers[i])) {
      return i;
    }
  }
  return 0;
}

typedef struct Scorer {
  MsArena *arena;
  MsFinding finding;
  int64_t by_tier[5];
} Scorer;

static void add(Scorer *s, const char *tier, MsSpan change, const char *term, int64_t weight) {
  ms_spans_push(s->arena, &s->finding.changes, change);
  ms_spans_push(s->arena, &s->finding.terms, ms_message_format(s->arena, "%s +%z", term, (size_t)weight));
  s->by_tier[tier_rank(text(tier))] += weight;
  s->finding.score += weight;
}

static MsSpan tier_of(const Scorer *s) {
  const char *const tiers[] = {"CONTRACT", "EFFECT+", "ERROR", "RESOURCE", "INTERNAL"};
  size_t best = 4;
  for (size_t i = 0; i < 5; i++) {
    if (s->by_tier[i] > 1 && i < best) {
      best = i;
    }
  }
  return text(tiers[best]);
}

/* Entries of `head` that `base` lacks. */
static MsSpans added(MsArena *arena, const MsSpans *head, const MsSpans *base) {
  MsSpans out = {0};
  for (size_t i = 0; i < head->len; i++) {
    if (!ms_spans_contains(base, head->ptr[i])) {
      ms_spans_push(arena, &out, head->ptr[i]);
    }
  }
  return out;
}

static MsSpan or_none(MsSpan value) {
  return value.len == 0 ? text("none") : value;
}

static MsSpan visibility(bool exported) {
  return text(exported ? "exported" : "private");
}

static void compare(Scorer *s, const MsFact *h, const MsFact *b) {
  MsArena *arena = s->arena;
  if (h->exported != b->exported) {
    add(s, "CONTRACT", ms_message_format(arena, "visibility: %S -> %S", visibility(b->exported), visibility(h->exported)), "contract", 8);
  }
  if (!ms_span_equal(h->ty, b->ty)) {
    if (h->exported) {
      add(s, "CONTRACT", ms_message_format(arena, "type: %S -> %S", b->ty, h->ty), "contract", 8);
    } else {
      add(s, "INTERNAL", ms_message_format(arena, "private type: %S -> %S", b->ty, h->ty), "signature", 1);
    }
  }
  const MsSpans permits = added(arena, &h->permits, &b->permits);
  if (permits.len > 0) {
    add(s, "EFFECT+", ms_message_format(arena, "permits: + %S", ms_spans_joined(arena, &permits, ", ")), "effect_permit", 7);
  }
  const MsSpans reach = added(arena, &h->reach, &b->reach);
  if (reach.len > 0) {
    add(s, "EFFECT+", ms_message_format(arena, "reaches: + %S", ms_spans_joined(arena, &reach, ", ")), "effect_reach", 6);
  }
  if (!ms_span_equal(h->error, b->error)) {
    add(s, "ERROR", ms_message_format(arena, "error type: %S -> %S", or_none(b->error), or_none(h->error)), "error_flow", 5);
  }
  if (h->tries != b->tries) {
    add(s, "ERROR", ms_message_format(arena, "try sites: %z -> %z", b->tries, h->tries), "error_flow", 5);
  }
  if (h->scopes != b->scopes) {
    add(s, "RESOURCE", ms_message_format(arena, "resource scopes: %z -> %z", b->scopes, h->scopes), "resource", 4);
  }
}

static bool has_any(const MsSpans *have, const MsSpans *want) {
  for (size_t i = 0; i < want->len; i++) {
    if (ms_spans_contains(have, want->ptr[i])) {
      return true;
    }
  }
  return false;
}

/* Follows callees that carry a gained effect down to where it enters, choosing the first name at each step. */
static MsSpan effect_path(MsArena *arena, const MsFact *start, const MsSpans *gained, const MsFactModel *head) {
  MsSpans path = {0};
  MsSpans seen = {0};
  ms_spans_push(arena, &path, start->name);
  ms_spans_push(arena, &seen, start->key);
  const MsFact *current = start;
  for (;;) {
    const MsFact *next = NULL;
    for (size_t i = 0; i < current->calls.len && next == NULL; i++) {
      const MsFact *callee = ms_fact_find(head, current->calls.ptr[i]);
      if (callee != NULL && !ms_spans_contains(&seen, current->calls.ptr[i]) && has_any(&callee->reach, gained)) {
        next = callee;
      }
    }
    if (next == NULL) {
      break;
    }
    ms_spans_push(arena, &seen, next->key);
    ms_spans_push(arena, &path, next->name);
    current = next;
  }
  if (current->external.len > 0) {
    ms_spans_push(arena, &path, current->external.ptr[0]);
  }
  return ms_message_format(arena, "path: %S", ms_spans_joined(arena, &path, " -> "));
}

/* Returns whether the change is scored (it has changes and a score above the `added` or `removed` base of 1). */
static bool classify(MsArena *arena, MsSpan key, const MsFact *h, const MsFact *b, bool base_checked, const MsFactModel *head,
                     MsFinding *out) {
  const MsFact *subject = h != NULL ? h : b;
  Scorer s = {.arena = arena};
  s.finding.id = key;
  s.finding.entity = subject->name;
  s.finding.location = ms_message_format(arena, "%S:%z", subject->file, subject->line);
  if (h != NULL && b == NULL && base_checked) {
    add(&s, "INTERNAL", text("added"), "added", 1);
    if (h->permits.len > 0) {
      add(&s, "EFFECT+", ms_message_format(arena, "permits: + %S", ms_spans_joined(arena, &h->permits, ", ")), "effect_permit", 7);
    }
    if (h->reach.len > 0) {
      add(&s, "EFFECT+", ms_message_format(arena, "reaches: + %S", ms_spans_joined(arena, &h->reach, ", ")), "effect_reach", 6);
    }
    if (h->exported) {
      add(&s, "CONTRACT", ms_message_format(arena, "added exported %S", h->kind), "contract", 8);
    }
  } else if (h == NULL && b != NULL) {
    add(&s, "INTERNAL", text("removed"), "removed", 1);
    if (b->exported) {
      add(&s, "CONTRACT", ms_message_format(arena, "removed exported %S", b->kind), "contract", 8);
    }
  } else if (h != NULL && b != NULL) {
    compare(&s, h, b);
  }
  if (h == NULL) {
    s.finding.tier = tier_of(&s);
    *out = s.finding;
    return false;
  }
  if (b != NULL) {
    const MsSpans reach = added(arena, &h->reach, &b->reach);
    if (reach.len > 0) {
      ms_spans_push(arena, &s.finding.evidence, effect_path(arena, h, &reach, head));
    }
  }
  const bool scored = s.finding.changes.len > 0 && s.finding.score > 1;
  s.finding.tier = tier_of(&s);
  *out = s.finding;
  return scored;
}

/* The number of distinct project entities that transitively call `key`. */
static size_t reach_count(const MsFactModel *head, MsSpan key) {
  MsArena scratch = ms_arena_new();
  MsSpans seen = {0};
  ms_spans_push(&scratch, &seen, key);
  for (size_t next = 0; next < seen.len; next++) {
    for (size_t i = 0; i < head->entities.len; i++) {
      const MsFact *caller = &head->entities.ptr[i];
      if (ms_spans_contains(&caller->calls, seen.ptr[next]) && !ms_spans_contains(&seen, caller->key)) {
        ms_spans_push(&scratch, &seen, caller->key);
      }
    }
  }
  const size_t count = seen.len - 1;
  ms_arena_free(&scratch);
  return count;
}

static int64_t compare_findings(uint8_t *env, const uint8_t *left, const uint8_t *right) {
  (void)env;
  const MsFinding *a = (const MsFinding *)(const void *)left;
  const MsFinding *b = (const MsFinding *)(const void *)right;
  if (a->score != b->score) {
    return b->score > a->score ? 1 : -1;
  }
  const size_t ra = tier_rank(a->tier);
  const size_t rb = tier_rank(b->tier);
  if (ra != rb) {
    return ra < rb ? -1 : 1;
  }
  return ms_span_compare(a->id, b->id);
}

/* Maps changed head lines to the most specific entity containing them: the smallest range, ties by key. */
static MsSpans touched_keys(MsArena *arena, const MsFactModel *head, const MsTouchedList *touched) {
  MsSpans result = {0};
  for (size_t t = 0; t < touched->len; t++) {
    for (size_t l = 0; l < touched->ptr[t].count; l++) {
      const int64_t line = touched->ptr[t].lines[l];
      const MsFact *best = NULL;
      for (size_t i = 0; i < head->entities.len; i++) {
        const MsFact *f = &head->entities.ptr[i];
        if (f->first == 0 || !ms_span_equal(f->file, touched->ptr[t].file) || line < (int64_t)f->first || line > (int64_t)f->last) {
          continue;
        }
        const int64_t span = (int64_t)f->last - (int64_t)f->first;
        const int64_t best_span = best == NULL ? 0 : (int64_t)best->last - (int64_t)best->first;
        if (best == NULL || span < best_span || (span == best_span && ms_span_compare(f->key, best->key) < 0)) {
          best = f;
        }
      }
      if (best != NULL && !ms_spans_contains(&result, best->key)) {
        ms_spans_push(arena, &result, best->key);
      }
    }
  }
  return result;
}

MsFindings ms_compare_facts(MsArena *arena, const MsFactModel *base, const MsFactModel *head, const MsDiffInput *input) {
  MsSpans keys = {0};
  for (size_t i = 0; i < head->entities.len; i++) {
    ms_spans_push(arena, &keys, head->entities.ptr[i].key);
  }
  for (size_t i = 0; i < base->entities.len; i++) {
    if (!ms_spans_contains(&keys, base->entities.ptr[i].key)) {
      ms_spans_push(arena, &keys, base->entities.ptr[i].key);
    }
  }
  ms_sort((uint8_t *)keys.ptr, keys.len, sizeof(MsSpan), ms_sort_compare_spans, NULL);
  const MsSpans touched = touched_keys(arena, head, &input->touched);
  MsFindings findings = {0};
  MsSpans scored_keys = {0};
  for (size_t k = 0; k < keys.len; k++) {
    const MsSpan key = keys.ptr[k];
    const MsFact *h = ms_fact_find(head, key);
    const MsFact *b = ms_fact_find(base, key);
    if (b != NULL && ms_spans_contains(&input->added, b->file)) {
      b = NULL;
    }
    MsFinding f = {0};
    const bool scored = classify(arena, key, h, b, input->base_checked, head, &f);
    bool has_callers = false;
    for (size_t i = 0; i < head->entities.len && !has_callers; i++) {
      has_callers = ms_spans_contains(&head->entities.ptr[i].calls, key);
    }
    if (scored && has_callers) {
      ms_spans_push(arena, &scored_keys, key);
    } else if (scored && h != NULL && h->exported) {
      ms_spans_push(arena, &f.terms, text("exported +3"));
      f.score += 3;
    }
    if (f.changes.len == 0 && ms_spans_contains(&touched, key)) {
      ms_spans_push(arena, &f.changes, text("body changed"));
    }
    if (f.changes.len == 0) {
      continue;
    }
    ms_findings_push(arena, &findings, f);
  }
  for (size_t i = 0; i < findings.len; i++) {
    MsFinding *f = &findings.ptr[i];
    if (!ms_spans_contains(&scored_keys, f->id)) {
      continue;
    }
    const size_t r = reach_count(head, f->id);
    f->reach = r;
    if (r > 0) {
      size_t bits = 0;
      for (size_t v = r; v > 0; v >>= 1) {
        bits++;
      }
      const int64_t weight = (int64_t)(2 * bits);
      ms_spans_push(arena, &f->terms, ms_message_format(arena, "reach(%z) +%z", r, (size_t)weight));
      f->score += weight;
    }
    const MsFact *h = ms_fact_find(head, f->id);
    if (h != NULL && h->exported) {
      ms_spans_push(arena, &f->terms, text("exported +3"));
      f->score += 3;
    }
  }
  ms_sort((uint8_t *)findings.ptr, findings.len, sizeof(MsFinding), compare_findings, NULL);
  return findings;
}
