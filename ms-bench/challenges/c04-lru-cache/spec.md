# LRU cache

The first line of input is the cache capacity `C` (an integer >= 1). Each following line is a command;
keys and values are non-empty tokens without spaces.

- `put K V`: store `K` with value `V` and mark it most recently used. If `K` already exists its value is
  replaced. If the cache then holds more than `C` entries, evict the least recently used one.
  Prints nothing.
- `get K`: print the value for `K` and mark it most recently used, or `miss` if absent.
- `keys`: print the keys from most to least recently used, separated by single spaces
  (an empty line when the cache is empty).

Blank lines are ignored.

Example input:

    2
    put a 1
    put b 2
    get a
    put c 3
    get b
    keys

Output:

    1
    miss
    c a
