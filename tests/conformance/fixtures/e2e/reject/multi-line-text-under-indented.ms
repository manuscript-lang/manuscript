// conform: tags=testing,tier-core
// conform: phase=check
export fn main() Int:
    text := """
        deep
      shallow
        """
    return text.length()
