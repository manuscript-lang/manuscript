type Page:
    annotated: String = "{"http://example.test"}" // the real note
    unannotated: String = "{"http://example.test"}"
    nested: String = "{"nested {"https://example.test"}"}" // deeply nested
    escaped: String = "\" // still text" // escaped quote
