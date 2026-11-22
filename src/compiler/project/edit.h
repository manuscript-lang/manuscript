/* compiler/project/edit.h: edits to ms.toml for `ms add` and `ms remove`. They change the dependency tables and keep
 * every comment and the formatting of the rest of the file. Port of crates/ms-driver/src/project/edit.rs. */
#ifndef MS_PROJECT_EDIT_H
#define MS_PROJECT_EDIT_H

#include "base/arena.h"
#include "base/safe.h"
#include "compiler/project/manifest.h"

/* The dependency `name = { url = ..., <kind> = <pin> }` to add. */
typedef struct MsDependencyEdit {
  MsSpan name;
  MsSpan url;
  MsSourceKind kind;
  MsSpan pin; /* the tag, the commit or the version requirement */
} MsDependencyEdit;

/* The name `ms add` gives a repository URL: its last path segment without `.git` and without a leading `ms-`, so
 * `https://github.com/acme/ms-pg.git` is `@pg`. False when that is not a valid name. */
MS_NODISCARD bool ms_edit_default_name(MsArena *arena, MsSpan url, MsSpan *name);

/* `text` with the dependency under `[dependencies]`. On failure `*error` says why. */
MS_NODISCARD bool ms_edit_add_dependency(MsArena *arena, MsSpan text, const MsDependencyEdit *dependency,
                                         MsSpan *out, MsSpan *error);

/* `text` allowing `name` the `effects` it declares, under `[effects]`. */
MS_NODISCARD bool ms_edit_allow_effects(MsArena *arena, MsSpan text, MsSpan name, const MsSpan *effects,
                                        size_t count, MsSpan *out, MsSpan *error);

/* `text` without `name` in `[dependencies]` and `[effects]`; false when it was not a dependency. */
MS_NODISCARD bool ms_edit_remove_dependency(MsArena *arena, MsSpan text, MsSpan name, MsSpan *out,
                                            MsSpan *error);

#endif
