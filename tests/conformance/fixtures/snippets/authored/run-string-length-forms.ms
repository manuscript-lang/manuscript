// conform: tags=strings,tier-core
// conform: phase=run
// conform: origin=retire-ms-rt-hot
// The scalar length of inline, heap, flagged and non-ASCII strings agrees on every backend.
export fn main() Int:
    inline := "hello"
    inline_wide := "h\u{e9}llo"
    heap_ascii := "plain ascii text that is also longer than fifteen bytes"
    heap_wide := "h\u{e9}llo w\u{f6}rld, this one is long enough to not be inline"
    built := inline + "-" + inline_wide
    print(inline.length())
    print(inline_wide.length())
    print(heap_ascii.length())
    print(heap_wide.length())
    print(built.length())
    print("".length())
    return 0
