/* compiler/project/solve_internal.h: what the resolver's files share. */
#ifndef MS_PROJECT_SOLVE_INTERNAL_H
#define MS_PROJECT_SOLVE_INTERNAL_H

#include "compiler/project/solve.h"

/* A requirement some manifest makes of a repository. */
typedef struct Ask {
  MsSpan asker; /* `the project` or a copy's id */
  MsSpan alias;
  const MsDependency *dep;
  MsSpan repo;
  bool nested;
} Ask;

/* A copy to build: the repository and bucket (or pin) it stands for. */
typedef struct Group {
  MsSpan repo;
  bool has_bucket;
  MsBucket bucket;
} Group;

typedef struct Choice {
  Group group;
  MsSpan url;
  MsSpan reference;
} Choice;

typedef struct Download {
  MsSpan url;
  MsSpan reference;
  MsFetched fetched;
} Download;

typedef struct VersionTag {
  MsVersion version;
  MsSpan tag;
} VersionTag;

typedef struct TagSet {
  MsSpan repo;
  VersionTag *tags;
  size_t count;
} TagSet;

MS_LIST_DEFINE(AskList, ask_list, Ask)
MS_LIST_DEFINE(ChoiceList, choice_list, Choice)
MS_LIST_DEFINE(DownloadList, download_list, Download)
MS_LIST_DEFINE(TagSetList, tag_set_list, TagSet)
MS_LIST_DEFINE(AskPointerList, ask_pointer_list, const Ask *)

typedef struct Solver {
  MsArena *arena;
  const MsResolveRequest *request;
  AskList asks;
  ChoiceList chosen;
  DownloadList downloads;
  TagSetList tags;
  MsSpan *error;
} Solver;

/* Orders spans by bytes. */
int span_compare(MsSpan a, MsSpan b);
/* Whether `name` is one of `count` spans. */
bool span_in_list(const MsSpan *names, size_t count, MsSpan name);
/* The id of the copy a choice names. */
MsSpan choice_id(Solver *s, const Choice *choice);
bool group_equal(const Group *a, const Group *b);
const Download *find_download(const Solver *s, MsSpan url, MsSpan reference);
bool solver_fail(Solver *s, MsSpan message);

/* solve_choose.c: the picks for the asks of one round, and their downloads. False with the error set. */
bool solver_choose(Solver *s, ChoiceList *next);

#endif
