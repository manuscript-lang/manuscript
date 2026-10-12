---
name: change-memory
description: Preserve durable lessons from Manuscript changes, user corrections, bugs, or reviews, and reconcile existing expert knowledge when decisions or evidence change.
---

# Change memory

Use [the expert protocol](../../.experts/README.md) for routing, authority, and the entry format. This skill closes the learning loop during ordinary work or backfills it when the user asks to learn from previous interactions.

1. Read the relevant expert entries and the evidence from the work. For historical backfills, inspect actual user messages, changes, and checks; chat titles and assistant completion reports are discovery aids, not proof. Follow corrections through to the latest decision.
2. Identify what would change a future implementation or review: a non-obvious constraint, an accepted or rejected choice worth retaining, a failure mechanism, or a check that caught a regression. Separate an explicit decision from verified behavior and a hypothesis. Preserve uncertainty as an open question only when it affects future work.
3. Put prevention in the strongest appropriate home. Observable regressions belong in behavioral tests; deterministic drift belongs in the existing check or generator; exact semantics belong in canonical design; terminology belongs in the glossary. Keep the expert entry focused on the reason, evidence, and trigger for reaching that home. Change a workflow skill only when the lesson changes the workflow, and a taste preference only when the user's direction supports generalizing it.
4. Update the existing entry in place, merging repeated evidence and replacing superseded guidance. A newer explicit request can supersede a remembered decision before its implementation ships: record the direction, link the actual request, and state what still needs checkout verification. Do not present an in-progress conversation as completed behavior. Add an expert and index route only when a distinct domain needs one. Keep memory changes reviewable alongside the implementation; during read-only reviews, report proposed updates rather than editing files.

If a lesson changes a domain workflow, update the relevant skill from [AGENTS.md](../../AGENTS.md#domain-skills); preserve concise workflow guidance and link to the expert evidence. Update catalog routes and both discovery directories when a skill is added, renamed, or removed.

Finish when the next agent can find the lesson, tell what establishes it, and perform a concrete verification. Mention the useful memory changes in the result. If no durable lesson emerged, leave memory unchanged.
