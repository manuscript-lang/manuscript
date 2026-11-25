[Wiki](../index.md) › [Benchmarks and performance](index.md)

# A long function must cost time and memory linear in its size

Four per-function structures were quadratic in a function of thousands of statements: the dominator fixed point walked the tree from every predecessor of the shared exit, threading and twins walked `idom` per dominance query, `share_exits` swept every edge per exit, and implicit-owner elaboration allocated a value-sized bit set per block. Now: Lengauer-Tarjan dominators, one shared interval tree (`mir_dom_tree`, `mir_dominates`), one sweep for exits, one stamp array. `ms emit --opt` of a 4000-statement function: 5.8 s and 500 MB to 2.1 s and 116 MB, output identical. Range analysis still clones an environment per block (about 6 percent at 2000 statements).

Lesson: test 1000, 2000 and 4000 statement functions; per-block arrays sized by values are blocks times values.
