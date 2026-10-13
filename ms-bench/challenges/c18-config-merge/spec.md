# Layered config merge

Applications often load several configuration layers (defaults, environment, local overrides) and merge
them. The input is a stack of layers in an INI-like format. Later layers override earlier ones. Print the
merged configuration with all `${...}` references expanded.

## Input format

Lines are first trimmed of leading and trailing spaces (only the space character). Then:

- An empty line, or one starting with `#`, is ignored.
- A line starting with `--- ` (three dashes and a space) followed by a non-empty name (after trimming)
  starts a new **layer** with that name (any characters). A new layer starts in the section `global`.
  Everything before the first layer header must be blank or a comment; anything else is an error
  (`expected layer header`, reported with layer name `input`).
- `[name]` switches the current section. A *name* (for sections and keys) is a lowercase letter followed
  by lowercase letters, digits or underscores. The section stays in effect until the next section line
  or layer header. Keys before any section line belong to `global`. `[global]` is allowed explicitly.
- `key = value` sets a key in the current section. The text before the first `=` is the key, trimmed; the
  text after it is the value, trimmed (it may be empty and may itself contain `=`, `#` and any other
  characters). Setting a key again, in the same or a later layer, replaces its value.
- `@unset section.key` removes that key from the configuration built so far (it is not an error if the
  key does not exist; a later layer can set it again). Exactly one space separates the directive and its
  argument, the argument is `<name>.<name>`.

## Syntax errors

Processing is line by line; the first error stops everything and prints exactly one line

    error: <layer>:<line>: <message>

where `<line>` is the 1-based physical line number in the input and `<message>` is one of:

- `expected layer header`: a non-blank, non-comment line before the first layer header
- `bad section name`: a line starting with `[` that does not end with `]` or whose inside is not a name
- `bad directive`: a line starting with `@` that is not a well-formed `@unset section.key`
- `bad key`: a line containing `=` (and not starting with `[`, `@` or `#`) whose key is not a name
- `invalid line`: anything else (for example a line with neither `=` nor a recognised form)

The checks apply in the order listed above, top to bottom, to the trimmed line (a layer header is
recognised before all of them).

## Interpolation

After all layers are merged, expand references in every value. In a value:

- `$$` stands for a literal `$`;
- `${section.key}` is replaced by the **fully expanded** value of that key in the merged configuration
  (use `global.key` for a global key);
- a `$` followed by anything else is a literal `$`.

Keys are expanded in sorted order of `section.key` (byte order), each by depth-first, left-to-right
evaluation; the first problem found stops everything and prints one line `error: <section>.<key>: <message>`
naming the key whose value contained the problem (for a cycle, the key that is reached again while it is
still being expanded):

- `bad reference`: `${` with no closing `}`, or the text inside is not `<name>.<name>`
- `unknown reference ${section.key}`: a well-formed reference to a key that does not exist
- `cycle`

## Output

The merged configuration, sections in byte order of their names, keys in byte order within a section,
as

    [section]
    key = value

with one empty line between sections. Sections without keys are not printed. With no keys at all, print
nothing.

Example input:

    # defaults
    --- defaults
    name = demo
    [server]
    host = localhost
    port = 8080
    debug = true
    url = http://${server.host}:${server.port}/${global.name}
    --- production
    [server]
    host = example.com
    port = 443
    @unset server.debug
    price = $$5 for $name

Output:

    [global]
    name = demo

    [server]
    host = example.com
    port = 443
    price = $5 for $name
    url = http://example.com:443/demo
