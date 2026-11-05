# Documentation screenshots

Screenshots live in `website/static/images/`, with a `-dark` variant next to each light image. A page embeds one with ordinary Markdown, and the `render-image` hook picks the variant for the reader's theme:

```markdown
![Alt text that says what the picture shows](/images/code-map-behavior.png "Optional caption")
```

Alt text is required and the path must start with `/images/`; the book build fails otherwise.

Regenerate a code-map screenshot from a project:

```sh
ms diagram ms.toml --format html --diff change.patch -o map.html
node website/screenshots/capture.cjs map.html run_command code-map Behavior Calls
```

The script needs Playwright with Chromium on the machine that runs it; the repository does not depend on it. Reduce each PNG before committing (for example to 128 colors); screenshots are about 150 KB.
