// The glob matcher is shared with `fs.glob`'s directory walk, so it stays native.
// A leading `windows` flag selects the dialect: path separators are read as slashes when set.
export extern fn msstd_path_matches_glob(
    windows: Bool,
    path: String,
    pattern: String
) Bool!
