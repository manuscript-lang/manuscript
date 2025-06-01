---
title: "Installation: Gearing Up for Your Manuscript Adventure!"
linkTitle: "Installation"
description: >
  How to install Manuscript and set up your development environment without breaking a sweat (probably). Let's get your tools ready!
---

Welcome, future Manuscript virtuoso! Before you can start crafting elegant code symphonies, you'll need to get Manuscript installed and your development environment tuned up. Think of this as gathering your enchanted tools before embarking on a grand quest. And good news: since Manuscript compiles to Go, a lot of the heavy lifting is already familiar territory if you've met Go before.

## Your Pre-Quest Checklist: Prerequisites

Every adventurer needs a few key items in their backpack. For this quest, make sure you have:

- **Go**: Version 1.22 or later. Go is the magical forge Manuscript uses behind the scenes.
- **Git**: For fetching the Manuscript source code from its mountain stronghold (GitHub).

## Acquiring Go: The Engine of Manuscript

If you don't yet have Go installed on your system, let's get that sorted. It's like installing the power crystal for your Manuscript compiler.

### macOS: The Homebrew Method (Our Favorite Potion)
If you're on a Mac and have [Homebrew](https://brew.sh/) (the friendly package manager for macOS), it's as easy as asking it to fetch Go:
```bash
brew install go
```
Homebrew will handle the rest. Isn't that nice?

### Linux: The Classic Download & Setup
For Linux adventurers, you'll typically download it directly from the source:
```bash
# First, let's download the Go tarball (adjust version if needed)
# You can find the latest at https://golang.org/dl/
wget https://go.dev/dl/go1.22.0.linux-amd64.tar.gz

# Now, unpack it into /usr/local (a common spot for Go)
# You might need sudo for this command.
sudo tar -C /usr/local -xzf go1.22.0.linux-amd64.tar.gz

# Next, tell your system where to find Go. Add this to your shell's config file.
# If you use bash (common default):
echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
# If you use zsh:
# echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.zshrc

# Finally, refresh your shell so it knows about the new PATH.
source ~/.bashrc
# Or for zsh:
# source ~/.zshrc
```
Voilà! Go should now be ready for action.

### Windows: The Installer Path
For Windows users, the Go team provides a handy MSI installer.
1.  Head over to the official Go downloads page: [https://golang.org/dl/](https://golang.org/dl/)
2.  Download the Windows installer (it'll have an `.msi` extension).
3.  Run the installer and follow the friendly prompts. It'll set everything up, including the PATH. Easy peasy!

## Installing Manuscript: Forging Your Compiler!

With Go ready, it's time to get the Manuscript compiler itself, `msc`.

### From Source: The Artisan's Approach
You'll be building `msc` from its source code, like a true code blacksmith.

```bash
# 1. Clone the Manuscript repository from GitHub (its digital home).
git clone https://github.com/manuscript-lang/manuscript.git

# 2. Navigate into the newly cloned directory.
cd manuscript

# 3. Fire up the forge! (Build the msc compiler).
# This 'make' command reads instructions from a Makefile to build the compiler.
make build-msc

# After a few moments of digital hammering and clanking,
# the shiny new 'msc' binary (the compiler program) will appear in a './build/' directory.
# Specifically, it will be at ./build/msc
```

### Adding `msc` to Your PATH: The VIP Pass
To use `msc` from anywhere in your terminal without typing its full path, you need to add its location to your system's PATH environment variable. This is like giving `msc` a VIP pass to your command line.

Replace `/path/to/manuscript/build` with the actual absolute path to the `build` directory inside the `manuscript` folder you cloned.
For example, if you cloned `manuscript` into `/Users/yourname/projects/manuscript`, the path would be `/Users/yourname/projects/manuscript/build`.

```bash
# For macOS/Linux:
# Add this line to your shell configuration file (e.g., ~/.bashrc or ~/.zshrc)
echo 'export PATH=$PATH:/path/to/manuscript/build' >> ~/.bashrc # Or ~/.zshrc
# Then, refresh your shell:
source ~/.bashrc # Or source ~/.zshrc

# Alternatively, for a more system-wide approach on macOS/Linux,
# you can create a symbolic link to a directory already in your PATH.
# This often requires sudo privileges.
sudo ln -s /path/to/manuscript/build/msc /usr/local/bin/msc
```

For Windows, you'd add the `build` directory (e.g., `C:\Users\yourname\projects\manuscript\build`) to your system's Path environment variable through the System Properties dialog. Search for "environment variables" in your Windows search bar.

## The Moment of Truth: Verify Installation

Let's make sure your Manuscript toolkit is correctly assembled and ready for action!

```bash
# 1. Check the version. This tells you if the 'msc' command is recognized.
msc --version
# You should see some version information printed.

# 2. Create a tiny test spell, a classic "Hello, World!"
echo 'fn main() { print("Hello from my shiny new Manuscript!") }' > test.ms

# 3. Compile and run your test spell.
msc test.ms
```

If everything is set up correctly, you should triumphantly see:
```
Hello from my shiny new Manuscript!
```

> Tools are now all set,
> Path is clear, the forge is hot,
> Code waits to be born.

If you see that message, congratulations! You've successfully installed Manuscript and are ready to start your coding adventures. High five!

## Editor Support: Making Your Spellbook Comfortable

While Manuscript is still young, here's how you can get some basic support in your favorite text editor:

### VS Code
- Official syntax highlighting and more robust language support are on the horizon! Stay tuned.

### Vim/Neovim
- For now, you can tell Vim/Neovim to treat `*.ms` files like Go files for syntax highlighting, which is a decent starting point. Add something like this to your `.vimrc` or `init.vim`:
  ```vim
  au BufNewFile,BufRead *.ms setf go
  ```

### Other Editors
- As a temporary measure, try associating `*.ms` files with Go syntax highlighting if your editor supports it.

## Next Steps: Your Adventure Continues!

Now that you're all set up, where to next on this grand Manuscript quest?

1.  **[Write Your First Program (Beyond Hello!)](../first-program/)**: Our "Hello World" tutorial actually goes a bit further to get you comfortable.
2.  **[Understand Manuscript's Philosophy (Language Overview)](../overview/)**: Get a feel for the design principles and goals behind Manuscript.
3.  **[Explore the Treasure Trove of Language Features](../../constructs/)**: Take a deep dive into all the cool things Manuscript can do.

## When Gremlins Attack: Troubleshooting Tips

Even the best adventurers sometimes encounter mischievous gremlins. Here's how to shoo some common ones away:

### Gremlin: "Go Not Found" or "go: command not found"
- **Solution:** This means your system can't find the Go executable. Double-check that Go is installed correctly (see the "Acquiring Go" section).
- Crucially, ensure that Go's `bin` directory (usually `/usr/local/go/bin` on Linux/macOS, or `C:\Go\bin` on Windows) is in your system's PATH. You can test this by typing:
  ```bash
  go version
  ```
  If this command works, Go is in your PATH. If not, revisit the PATH setup for your OS.

### Gremlin: "Build Errors" during `make build-msc`
- **Solution:**
    1. Make sure you have the latest Go version that Manuscript requires (see Prerequisites).
    2. Navigate back to your `manuscript` directory in the terminal.
    3. Try cleaning up previous build attempts and fetching Go module dependencies:
       ```bash
       cd /path/to/your/manuscript/clone # Make sure you're in the right place!
       go mod tidy  # Fetches and tidies Go module dependencies
       make clean   # Removes old build artifacts
       make build-msc # Try building again
       ```

### Gremlin: "Permission Denied" when trying to run `msc` (macOS/Linux)
- **Solution:** This usually means the `msc` file doesn't have execute permissions.
    - If you added `msc` to your PATH via symlink or by copying it, make sure the actual `build/msc` file is executable:
      ```bash
      chmod +x /path/to/manuscript/build/msc
      ```
    - If you're running it directly, like `./build/msc`, do the same:
      ```bash
      chmod +x ./build/msc
      ```

If you encounter other, more stubborn gremlins, don't hesitate to seek help from the Manuscript community (once such forums or issue trackers are established!). Happy installing!
