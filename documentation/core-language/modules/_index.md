+++
title = "Modules"
weight = 6
+++

# Modules

As a program grows, move related declarations into a file that has a clear responsibility: prices, configuration, or a service's operations. Each `.ms` file is a module. Use `export` to share declarations and `import` to use them.

Start by [defining a type in one file and using it in another](declarations.md#a-visible-contract). Then apply the same boundary to the [pricing calculation](boundaries.md). The import chapter keeps the exact rules for names, paths, constants, and visibility after the first working program. File boundaries organize a program; they do not require a package manifest just to import a neighboring file.

- [Imports and exports](declarations.md)
- [Module boundaries](boundaries.md)
