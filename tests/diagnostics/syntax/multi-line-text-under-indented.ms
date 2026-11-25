// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int {
    text := """
        deep
      shallow
        """
    return text.length()
}
// expect-error: MS1002 6:1 text line is indented less than the closing '"""'; indent it to the closing quotes' column, or move the closing quotes left
