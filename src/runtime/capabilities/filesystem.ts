// Filesystem Capability Adapters
import * as fs from "fs/promises";
import * as path from "path";
import { Glob } from "bun";
import type { Filesystem, FileInfo } from "./types";

// ============================================
// Local Filesystem
// ============================================

export interface LocalFilesystemConfig {
  root?: string;  // Optional root directory (for sandboxing)
}

export class LocalFilesystem implements Filesystem {
  private root: string;
  
  constructor(config: LocalFilesystemConfig = {}) {
    this.root = config.root || process.cwd();
  }
  
  private resolvePath(p: string): string {
    if (path.isAbsolute(p)) {
      return p;
    }
    return path.join(this.root, p);
  }
  
  async read(filePath: string): Promise<string> {
    return fs.readFile(this.resolvePath(filePath), "utf-8");
  }
  
  async readBytes(filePath: string): Promise<Uint8Array> {
    const buffer = await fs.readFile(this.resolvePath(filePath));
    return new Uint8Array(buffer);
  }
  
  async exists(filePath: string): Promise<boolean> {
    try {
      await fs.access(this.resolvePath(filePath));
      return true;
    } catch {
      return false;
    }
  }
  
  async stat(filePath: string): Promise<FileInfo> {
    const resolved = this.resolvePath(filePath);
    const stats = await fs.stat(resolved);
    return {
      path: resolved,
      name: path.basename(resolved),
      isDirectory: stats.isDirectory(),
      size: stats.size,
      modified: stats.mtime,
    };
  }
  
  async list(dirPath: string): Promise<FileInfo[]> {
    const resolved = this.resolvePath(dirPath);
    const entries = await fs.readdir(resolved, { withFileTypes: true });
    
    return Promise.all(entries.map(async (entry) => {
      const entryPath = path.join(resolved, entry.name);
      const stats = await fs.stat(entryPath);
      return {
        path: entryPath,
        name: entry.name,
        isDirectory: entry.isDirectory(),
        size: stats.size,
        modified: stats.mtime,
      };
    }));
  }
  
  async glob(pattern: string): Promise<string[]> {
    const glob = new Glob(pattern);
    const matches: string[] = [];
    for await (const file of glob.scan({ cwd: this.root })) {
      matches.push(file);
    }
    return matches;
  }
  
  async write(filePath: string, content: string): Promise<void> {
    const resolved = this.resolvePath(filePath);
    await fs.mkdir(path.dirname(resolved), { recursive: true });
    await fs.writeFile(resolved, content, "utf-8");
  }
  
  async writeBytes(filePath: string, content: Uint8Array): Promise<void> {
    const resolved = this.resolvePath(filePath);
    await fs.mkdir(path.dirname(resolved), { recursive: true });
    await fs.writeFile(resolved, content);
  }
  
  async append(filePath: string, content: string): Promise<void> {
    await fs.appendFile(this.resolvePath(filePath), content, "utf-8");
  }
  
  async mkdir(dirPath: string): Promise<void> {
    await fs.mkdir(this.resolvePath(dirPath), { recursive: true });
  }
  
  async remove(filePath: string): Promise<void> {
    const resolved = this.resolvePath(filePath);
    const stats = await fs.stat(resolved);
    if (stats.isDirectory()) {
      await fs.rm(resolved, { recursive: true });
    } else {
      await fs.unlink(resolved);
    }
  }
  
  async copy(src: string, dest: string): Promise<void> {
    await fs.copyFile(this.resolvePath(src), this.resolvePath(dest));
  }
  
  async move(src: string, dest: string): Promise<void> {
    await fs.rename(this.resolvePath(src), this.resolvePath(dest));
  }
  
  join(...parts: string[]): string {
    return path.join(...parts);
  }
  
  dirname(filePath: string): string {
    return path.dirname(filePath);
  }
  
  basename(filePath: string): string {
    return path.basename(filePath);
  }
  
  resolve(filePath: string): string {
    return this.resolvePath(filePath);
  }
}

// ============================================
// Mock Filesystem for Testing
// ============================================

export interface MockFilesystemConfig {
  files?: Record<string, string>;
}

export class MockFilesystem implements Filesystem {
  private files: Map<string, string>;
  private directories: Set<string>;
  
  constructor(config: MockFilesystemConfig = {}) {
    this.files = new Map(Object.entries(config.files || {}));
    this.directories = new Set();
    
    // Create directory entries for all files
    for (const filePath of this.files.keys()) {
      const dir = path.dirname(filePath);
      if (dir !== ".") {
        this.directories.add(dir);
      }
    }
  }
  
  // Test helpers
  getFiles(): Record<string, string> {
    return Object.fromEntries(this.files);
  }
  
  setFile(filePath: string, content: string): void {
    this.files.set(filePath, content);
  }
  
  async read(filePath: string): Promise<string> {
    const content = this.files.get(filePath);
    if (content === undefined) {
      throw new Error(`ENOENT: no such file or directory '${filePath}'`);
    }
    return content;
  }
  
  async readBytes(filePath: string): Promise<Uint8Array> {
    const content = await this.read(filePath);
    return new TextEncoder().encode(content);
  }
  
  async exists(filePath: string): Promise<boolean> {
    return this.files.has(filePath) || this.directories.has(filePath);
  }
  
  async stat(filePath: string): Promise<FileInfo> {
    const isDir = this.directories.has(filePath);
    const content = this.files.get(filePath);
    
    if (!isDir && content === undefined) {
      throw new Error(`ENOENT: no such file or directory '${filePath}'`);
    }
    
    return {
      path: filePath,
      name: path.basename(filePath),
      isDirectory: isDir,
      size: content?.length || 0,
      modified: new Date(),
    };
  }
  
  async list(dirPath: string): Promise<FileInfo[]> {
    const results: FileInfo[] = [];
    const prefix = dirPath === "." ? "" : dirPath + "/";
    
    for (const [filePath, content] of this.files) {
      if (filePath.startsWith(prefix)) {
        const relative = filePath.slice(prefix.length);
        if (!relative.includes("/")) {
          results.push({
            path: filePath,
            name: relative,
            isDirectory: false,
            size: content.length,
            modified: new Date(),
          });
        }
      }
    }
    
    for (const dir of this.directories) {
      if (dir.startsWith(prefix)) {
        const relative = dir.slice(prefix.length);
        if (!relative.includes("/")) {
          results.push({
            path: dir,
            name: relative,
            isDirectory: true,
            size: 0,
            modified: new Date(),
          });
        }
      }
    }
    
    return results;
  }
  
  async glob(pattern: string): Promise<string[]> {
    const regex = new RegExp(
      "^" + pattern
        .replace(/\./g, "\\.")
        .replace(/\*\*/g, "{{GLOBSTAR}}")
        .replace(/\*/g, "[^/]*")
        .replace(/{{GLOBSTAR}}/g, ".*")
      + "$"
    );
    
    return [...this.files.keys()].filter(f => regex.test(f));
  }
  
  async write(filePath: string, content: string): Promise<void> {
    this.files.set(filePath, content);
    const dir = path.dirname(filePath);
    if (dir !== ".") {
      this.directories.add(dir);
    }
  }
  
  async writeBytes(filePath: string, content: Uint8Array): Promise<void> {
    await this.write(filePath, new TextDecoder().decode(content));
  }
  
  async append(filePath: string, content: string): Promise<void> {
    const existing = this.files.get(filePath) || "";
    this.files.set(filePath, existing + content);
  }
  
  async mkdir(dirPath: string): Promise<void> {
    this.directories.add(dirPath);
  }
  
  async remove(filePath: string): Promise<void> {
    this.files.delete(filePath);
    this.directories.delete(filePath);
  }
  
  async copy(src: string, dest: string): Promise<void> {
    const content = await this.read(src);
    await this.write(dest, content);
  }
  
  async move(src: string, dest: string): Promise<void> {
    const content = await this.read(src);
    await this.write(dest, content);
    await this.remove(src);
  }
  
  join(...parts: string[]): string {
    return path.join(...parts);
  }
  
  dirname(filePath: string): string {
    return path.dirname(filePath);
  }
  
  basename(filePath: string): string {
    return path.basename(filePath);
  }
  
  resolve(filePath: string): string {
    return path.resolve(filePath);
  }
}
