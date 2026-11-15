type Page:
    annotated: String = f"{"http://example.test"}" // the real note
    unannotated: String = f"{"http://example.test"}"
    nested: String = f"{f"nested {"https://example.test"}"}" // deeply nested
    escaped: String = "\" // still text" // escaped quote
