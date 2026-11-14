# HTML parse

`@std/data/html` `parse` on a generated page (2,000 blocks of headings, paragraphs, lists, tables, entities and attributes, 396,806 bytes) and on 5,000 nested `div` elements. The tokenizer and tree builder are Manuscript; only character-reference decoding is a Rust primitive.

```sh
ms run bench/perf/html/ms
```

Compare numbers only from the same machine.

## 2026-11-14, Linux amd64, 4 cores, main at cf172d6b plus the Manuscript port

| Parser | Page | 5,000 nested divs |
| --- | ---: | ---: |
| Rust tokenizer and tree builder (before) | 23.6 ms | 2.1 ms |
| Manuscript `@std/data/html` (after) | 21.4-22.4 ms | 1.8-1.9 ms |

The port is 0.91-0.95x the time on the page and 0.86-0.9x on deep nesting. Deeply nested and repeated-tag inputs scale linearly from 2,500 to 100,000 elements; only mis-nested formatting (`<b><i>x</b>y` repeated) grows slightly super-linearly, as in the Go parser it follows.
