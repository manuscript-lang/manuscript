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

## Feature screencast

`website/static/images/screencast.gif` is the docs home screencast and is reusable in the README. Regenerate it with a built `ms` (add `--mp4 out.mp4` for a social-media video; needs ffmpeg):

```sh
python3 website/screenshots/screencast.py --ms target/release/ms
```

Scenes and captions are listed in `SCENES` in the script; sources live in `website/screenshots/screencast/`. Every command runs for real, so the output shown is current compiler output. The script needs Python 3 with Pillow and DejaVu Sans Mono (not project dependencies). Re-run it when a shown diagnostic or command output changes.
