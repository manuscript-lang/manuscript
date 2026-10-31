---
name: improve-documentation
description: Audit and improve Manuscript documentation as a whole, including current-main accuracy, marketing, onboarding, chapter progression, navigation, and rendered quality.
---

# Improve documentation

Use when asked to revamp, reorganize, refresh, or substantially improve the docs,
or make the landing page more compelling. For a narrow correction, use
[documentation](../documentation/SKILL.md) directly. Apply that skill's ownership
and validation rules throughout this workflow.

Read [VISION.md](../../VISION.md) for positioning and the
[documentation lessons](../../wiki/tooling-and-docs/index.md) for prior decisions.
The user's current direction takes precedence over older preferences. The
landing page is a marketing page intended to get people to try Manuscript;
learning pages help them succeed after that click.

Choose the relevant steps for the requested scope. A homepage revision uses the
marketing and rendered checks; a language refresh starts with behavior and
examples. Before editing, name the reader's task, the concrete obstacle, and the
observable result that would remove it. Improve quality through clearer structure,
examples, and deletion as well as new prose.

## 1. Establish what ships

- Compare the working branch with current `main` and inspect recent language,
  library, runtime, and CLI changes. Use implementation, declarations, and tests
  as evidence; a vision or historical completion report does not prove a feature
  exists. Record the revision used; report when current main is unavailable.
  Preserve unrelated work.
- Use `ms guide` and `ms search_symbol <name or words>` to discover current
  syntax and APIs, then follow relevant source and tests. Check whole behaviors:
  argument binding, defaults, mutation, error handling, and resource lifetimes.
- Remove obsolete guidance, commands, and pending designs that no longer apply.
  Check prose as well as code: examples can compile while their explanation is
  stale. Trace changed concepts through the README, tutorials, exact rules,
  library comments, CLI help, and agent cheat sheet where relevant; searching an
  old spelling alone misses obsolete claims and recommended patterns. Edit
  library prose in `stdlib/*.ms` and regenerate derived output. Check incoming
  links before deleting superseded design or verification records; retain useful
  current architecture and evidence.

## 2. Audit the reader's journey

Read the homepage, docs hub, quickstart, tour, task recipes, and section indexes
in sequence. Inspect [navigation](../../website/data/navigation.toml), page
titles/weights, breadcrumbs, and previous/next links alongside the prose.
Identify a few concrete obstacles and choose changes that remove them.
Use the same reading order in the sidebar, section indexes, and previous/next
links; keep navigation data as the shared source of ordering.

| Page's job | What a reader should get |
| --- | --- |
| Marketing homepage | A reason to try Manuscript, visible proof, and a clear first action. |
| Start here | A short path for a newcomer and useful routes for returning readers. |
| Quickstart | Download, run, edit, and build a real program with visible results. |
| Tour | Small examples that introduce concepts before depending on them. |
| Task recipe | A complete solution, its command and output, and relevant failure cases. |
| Language/API reference | Exact contracts with one canonical home for each rule. |
| Contributor guide | Implementation and maintenance details for repository work. |

Design titles, sections, and content together. Use learning, building, and
reference as distinct reader intents. Keep language semantics in the language
reference and compiler internals in contributor docs. Preserve useful routes
and anchors; update incoming links and add redirects when a move needs them.

## 3. Make the homepage worth acting on

- Use a focused visual hero: a large headline, a short description, the primary
  trial action, a secondary tour link, and a compact code/output preview. The
  user's later request for a hero replaces the earlier stacked benefit sections
  and cards. Keep supporting copy brief and remove repeated sales paragraphs.
- Lead with a concrete value proposition grounded in shipped features. Show a
  small runnable program, how to run it, and its actual output. Explain benefits
  through readable code, useful tools, and things people can build.
- Give the trial action visual priority and a direct path to the quickstart.
  Provide a secondary route to explore the language. Distinguish the marketing
  layout from documentation reading rails while keeping docs easy to reach.
- Use confident, engaging copy with honest development status and platform
  requirements. Claims about speed, adoption, reliability, or conversion need
  evidence. Keep aspirations identifiable as aspirations.
- Reuse the site's visual system and shared highlighting grammar. Work in
  project-owned Hugo overrides; preserve the vendored theme. Tailwind and Vercel
  are recorded design references for clarity, typography, and navigation.

## 4. Teach a path people can finish

- Put the first successful run before manifest internals and advanced options.
  Let readers change something and see the result, then build an executable.
  State working directories, prerequisites, platform differences, and what to
  expect. Link deeper explanations where they become useful.
  Check that the installed release supports the documented syntax and commands;
  identify any checkout-only prerequisites when teaching unreleased behavior.
- Use small, focused examples and plain explanations. Simplify the scenario
  before adding helper layers, domain models, or error hierarchies. Keep matches
  flat. Use current testing helpers and propagate failed assertions with `try`.
- Explain choices: absence versus failure, propagating versus inspecting an
  error, sharing versus cloning, and scoped resource cleanup. Link exact rules
  instead of duplicating them across chapters.
- Trim filler, repeated inventories, and obsolete implementation details.
  Keep coverage reports and review bookkeeping out of reader-facing pages.
  Write about Manuscript without language-comparison pages.
- For visual work, compare authored content with the base branch and preserve
  its meaning. For API references, show ordinary Manuscript declarations and
  readable classifications; keep generated JSON contracts and symbol anchors
  stable. Follow the existing documentation lessons for presentation details.

## 5. Verify the experience

- Check complete examples with `make docs-check` and run the published examples
  natively and exercise the actual displayed commands in disposable directories.
  Follow the complete first-run sequence, including downloads, paths, edits,
  arguments, and executable output. Use isolated files, stdin, and loopback
  fixtures for recipes; verify failure status and propagate write/flush errors.
- Run applicable `make docs-check`, `make repo-check`, and `make book-check`.
  Use `make book` for production output. The
  [publication checks](../../tests/docs/publication.test.cjs) validate prefixed
  links/anchors, generated references/downloads, and sidebar/reading order.
  Extend them for meaningful new navigation or landing-page contracts.
- Inspect desktop and mobile renders in light and dark themes. Check the primary
  action, code/output readability, highlighting, copy behavior, keyboard access,
  navigation, and page overflow. A successful HTML build does not establish
  visual quality. Use the environment's available browser tooling.
- Recheck against latest `main` before integration; resolve new API or command
  changes and repeat affected checks. After removals, generate with destination
  cleanup and search rendered pages, search data, and downloads for retired
  routes and terminology. When publishing is requested, verify the deployed site
  and reader artifacts separately from source generation or merge.

## 6. Leave durable guidance

Summarize the reader obstacles removed and the evidence for each improvement;
do not claim increased conversion without measurement. Report unavailable checks
and distinguish local changes, a merged PR, and a deployed site. Follow
[create-pr](../create-pr/SKILL.md) when PR work is requested.
Update the closest existing wiki page when a new user decision supersedes
older advice; keep exact rules and enforceable regressions in their canonical
docs or checks. Avoid creating parallel inventories of the same guidance.
