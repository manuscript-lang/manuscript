+++
title = "Maintenance and compatibility"
weight = 3
+++

# Maintain the repository

Check the shared version pin when reviewing an agent’s packaging change (repository root).

```sh
cat .msversion
```

```text
0.1.0
```

- Keep CLI, book and extension versions aligned.
- Alpha compatibility changes need migration guidance.

<span id="keep-the-feedback-loop-healthy"></span>
<span id="prepare-a-release"></span>
<span id="public-compatibility"></span>
<span id="refresh-pinned-inputs"></span>

Next: [release policy](https://github.com/manuscript-lang/manuscript/blob/main/AGENTS.md), [release workflow](https://github.com/manuscript-lang/manuscript/blob/main/.github/workflows/rust-dist.yml), and [checks](development.md).
