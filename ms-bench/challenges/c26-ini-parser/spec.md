# INI parser

Standard input has two parts separated by the first line that is exactly `---`: an INI document, then a list
of queries (one per line). If there is no `---` line, the whole input is the document and there are no queries.

## Parsing the document

Process the document line by line. Trim whitespace (spaces and tabs) from both ends of each line first, then:

1. An empty line, or a line starting with `;` or `#`, is ignored.
2. A line that starts with `[` and ends with `]` begins a section. The section name is the text between the
   brackets, trimmed (it may be empty). Reopening an existing section continues it.
3. Any other line containing `=` is a setting: split at the **first** `=`; the key is the left part trimmed,
   the value is the right part trimmed. If the value has at least two characters and begins and ends with a
   double quote (`"`), remove that outer pair of quotes (the text between them is kept as is, including
   spaces). A setting whose key is empty is ignored.
4. Every other line (no `=`, not a section) is ignored.

Settings before the first section header belong to the *global* section, which has no name. A later setting
with the same section and key replaces the earlier value. Names are case-sensitive. Section names and keys
in the test data never contain `.`.

## Queries

Trim each query line (spaces and tabs). Skip empty ones. A query without a `.` asks for a global key. A query
with a `.` is split at the **first** `.` into `section` and `key`. Print the value, or `<missing>` if the
section or key does not exist. An empty value prints an empty line.

Example input:

    name = demo
    [server]
    host = "example.com"
    port=8080
    ; comment
    [client]
    host = local host
    ---
    name
    server.host
    server.port
    client.host
    client.port
    nope.x

Output:

    demo
    example.com
    8080
    local host
    <missing>
    <missing>
