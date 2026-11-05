+++
title = "Modules"
weight = 6
+++

# Modules

As a program grows, move related declarations into a file that has a clear responsibility: prices, configuration, or a service's operations. Each `.ms` file is a module. Use `export` to share declarations and `import` to use them.

Start with the two-file [pricing example](boundaries.md) to see the boundary in use. Then read the import rules for names, paths, constants, and visibility. File boundaries organize a program; they do not require a package manifest just to import a neighboring file.

- [Imports and exports](declarations.md)
- [Module boundaries](boundaries.md)
