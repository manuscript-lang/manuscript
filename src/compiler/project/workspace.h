/* compiler/project/workspace.h: workspaces. A root `ms.toml` with `[workspace] members` names directories that each
 * hold a project. Members import one another through `{ path = "../util" }` dependencies and share the root's
 * `ms.lock`. */
#ifndef MS_PROJECT_WORKSPACE_H
#define MS_PROJECT_WORKSPACE_H

#include "compiler/project/manifest.h"

typedef struct MsWorkspaceMember {
  MsSpan name; /* [project] name, unique in the workspace */
  MsSpan root; /* the canonical directory holding the member's ms.toml */
} MsWorkspaceMember;

MS_LIST_DEFINE(WorkspaceMemberList, workspace_member_list, MsWorkspaceMember)

/* A workspace root and the members it lists, the root's own project first when it has one. */
typedef struct MsWorkspace {
  MsSpan root; /* the canonical directory holding the root ms.toml and ms.lock */
  WorkspaceMemberList members;
} MsWorkspace;

/* The workspace that contains the project whose `ms.toml` is `manifest` (absolute): the manifest itself when it has
 * [workspace], else the nearest ancestor manifest that lists this directory. `*found` is false for a project outside
 * any workspace. */
MS_NODISCARD bool ms_workspace_find(MsArena *arena, MsSpan manifest, MsWorkspace *out, bool *found,
                                    MsProjectError *error);

/* The members of `manifest` when it is a workspace root with no [project] of its own, so a command aimed at it
 * means "every member"; `*found` is false for any other manifest or file. */
MS_NODISCARD bool ms_workspace_root_members(MsArena *arena, MsSpan manifest, MsWorkspace *out, bool *found,
                                            MsProjectError *error);

/* The member whose directory is `dir`, or NULL. */
const MsWorkspaceMember *ms_workspace_member_at(const MsWorkspace *workspace, MsSpan dir);

/* The manifest file of `member`, in the arena. */
MsSpan ms_workspace_manifest(MsArena *arena, const MsWorkspaceMember *member);

void ms_workspace_free(MsWorkspace *workspace);

#endif
