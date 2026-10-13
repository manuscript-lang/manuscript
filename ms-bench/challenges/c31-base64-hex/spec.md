# Base64 and hex codec

Implement the encodings by hand (do not use a library encoder or decoder). Each non-blank input line is a
command and produces exactly one output line. Lines that are empty or contain only spaces are skipped.

A line is `COMMAND` or `COMMAND TEXT`: the command is the part before the **first** space and `TEXT` is
everything after that space, verbatim (it may contain spaces, including leading and trailing ones; if there
is no space, or nothing after it, `TEXT` is empty). All input is ASCII.

| command | meaning |
| --- | --- |
| `b64e` | Base64-encode the bytes of `TEXT` (standard alphabet `A-Za-z0-9+/`, padded with `=` to a multiple of 4) |
| `b64d` | Base64-decode `TEXT` and print the decoded text |
| `hexe` | hex-encode the bytes of `TEXT` using lowercase digits, two per byte |
| `hexd` | hex-decode `TEXT` (digits `0-9a-fA-F`) and print the decoded text |

Any other command prints `error`.

## Decoding rules

A decode command prints `error` unless all of these hold:

- **Base64**: the length is a multiple of 4 (empty is fine and decodes to empty text); every character is in
  the alphabet, except that `=` may appear only as the last one or two characters of the whole text; and the
  unused low bits of the last character before padding are zero (`QQ==` is valid for `A`, but `QR==` is not;
  `QUI=` is valid for `AB`, but `QUJ=` is not). A `=` anywhere else, or three or more `=`, is an error.
- **Hex**: the length is even and every character is a hex digit (upper or lower case).
- **Result**: every decoded byte must be a printable ASCII character, code 32 to 126 inclusive. Otherwise
  print `error`.

An empty result prints an empty line.

Example input:

    b64e Hello, World!
    b64d SGVsbG8sIFdvcmxkIQ==
    hexe Hi there
    hexd 4869207468657265
    b64d SGVsbG8
    hexd 4g
    b64d QR==
    hexd 00
    b64e
    nope x

Output:

    SGVsbG8sIFdvcmxkIQ==
    Hello, World!
    4869207468657265
    Hi there
    error
    error
    error
    error

    error
