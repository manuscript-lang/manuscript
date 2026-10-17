# Caesar and Vigenere ciphers

Each non-blank input line (blank means empty or only spaces) is a command with four parts:

    <cipher> <mode> <key> <text>

The first three parts are separated from each other and from the text by exactly one space. The text is
everything after the third space; it may contain spaces and any other characters, but must be non-empty.
Every command line produces exactly one output line.

- `cipher` is `caesar` or `vigenere`; `mode` is `enc` or `dec`.
- Letters `A-Z` and `a-z` are transformed and keep their case. Every other character (digits, spaces,
  punctuation, non-ASCII characters) is copied unchanged.
- **caesar**: `key` is a decimal integer with an optional leading `-` (no `+`), at most 7 digits. Encrypting
  shifts each letter forward in the alphabet by `key` positions, wrapping around (`key` may be negative or
  larger than 26); decrypting shifts backward by `key`.
- **vigenere**: `key` is one or more ASCII letters (either case; `A` and `a` both mean a shift of 0, `B`
  and `b` a shift of 1, and so on). The key letters are used cyclically, starting at the first key letter
  for the first letter of the text. The key position advances **only on letters of the text**, never on
  characters that are copied unchanged. Encrypting shifts forward by the current key letter, decrypting
  shifts backward.

Errors. The following checks are made in this order and the first failure decides the output:

1. Fewer than three spaces, or an empty text: `error: bad command`
2. Unknown cipher: `error: bad cipher`
3. Unknown mode (case-sensitive): `error: bad mode`
4. Invalid key for the chosen cipher: `error: bad key`

Example input:

    caesar enc 3 Hello, World!
    caesar dec 3 Khoor, Zruog!
    vigenere enc Key Attack at dawn
    vigenere dec Key Kxrkgi kx bkal
    rot13 enc 13 x
    caesar enc 3x abc
    caesar enc

Output:

    Khoor, Zruog!
    Hello, World!
    Kxrkgi kx bkal
    Attack at dawn
    error: bad cipher
    error: bad key
    error: bad command
