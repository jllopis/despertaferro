const std = @import("std");

pub const Error = error{
    InvalidHead,
    InvalidIndex,
    IndexMissing,
    NotBareRepository,
    NotGitRepository,
    UnsupportedHead,
    UnsupportedIndexVersion,
};

pub const WorktreeStatus = struct {
    tracked: u32 = 0,
    clean: u32 = 0,
    modified: u32 = 0,
    deleted: u32 = 0,

    pub fn dirty(self: WorktreeStatus) u32 {
        return self.modified + self.deleted;
    }
};

pub const Head = union(enum) {
    branch: []const u8,
    detached: []const u8,

    pub fn deinit(self: Head, allocator: std.mem.Allocator) void {
        switch (self) {
            .branch => |value| allocator.free(value),
            .detached => |value| allocator.free(value),
        }
    }
};

pub const BareRepository = struct {
    path: []const u8,
    head: Head,

    pub fn deinit(self: *BareRepository, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
        self.head.deinit(allocator);
        self.* = undefined;
    }
};

// Git index entry (v2/v3 on-disk layout, held in memory).
pub const IndexEntry = struct {
    ctime_s: u32,
    ctime_ns: u32,
    mtime_s: u32,
    mtime_ns: u32,
    dev: u32,
    ino: u32,
    mode: u32,
    uid: u32,
    gid: u32,
    size: u32,
    sha1: [20]u8,
    flags: u16,
    path: []const u8,

    pub fn deinit(self: IndexEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.path);
    }

    fn lessThan(_: void, a: IndexEntry, b: IndexEntry) bool {
        return std.mem.lessThan(u8, a.path, b.path);
    }
};

pub fn openBare(allocator: std.mem.Allocator, io: std.Io, repo_path: []const u8) !BareRepository {
    try requireGitDir(allocator, io, repo_path);

    const head_path = try std.fs.path.join(allocator, &.{ repo_path, "HEAD" });
    defer allocator.free(head_path);

    const head_data = std.Io.Dir.cwd().readFileAlloc(io, head_path, allocator, .limited(64 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return Error.NotGitRepository,
        else => return err,
    };
    defer allocator.free(head_data);

    return .{
        .path = try allocator.dupe(u8, repo_path),
        .head = try parseHead(allocator, head_data),
    };
}

pub fn statusWorktree(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo: BareRepository,
    worktree_path: []const u8,
) !WorktreeStatus {
    const index_path = try std.fs.path.join(allocator, &.{ repo.path, "index" });
    defer allocator.free(index_path);

    const index_data = std.Io.Dir.cwd().readFileAlloc(io, index_path, allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return Error.IndexMissing,
        else => return err,
    };
    defer allocator.free(index_data);

    return statusFromIndex(allocator, io, index_data, worktree_path);
}

// --- Item 7: stage a file into the git index ---

pub fn addPathToIndex(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo: BareRepository,
    worktree_path: []const u8,
    rel_path: []const u8,
) !void {
    if (!isSafeIndexPath(rel_path)) return error.InvalidPath;

    const full_path = try std.fs.path.join(allocator, &.{ worktree_path, rel_path });
    defer allocator.free(full_path);

    const file_data = try std.Io.Dir.cwd().readFileAlloc(io, full_path, allocator, .unlimited);
    defer allocator.free(file_data);

    const stat = try std.Io.Dir.cwd().statFile(io, full_path, .{});
    const sha1 = try writeBlobObject(allocator, io, repo, file_data);

    const index_path = try std.fs.path.join(allocator, &.{ repo.path, "index" });
    defer allocator.free(index_path);

    var entries = std.ArrayList(IndexEntry).empty;
    defer {
        for (entries.items) |e| e.deinit(allocator);
        entries.deinit(allocator);
    }

    const existing_data = std.Io.Dir.cwd().readFileAlloc(io, index_path, allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => null,
        else => return err,
    };
    if (existing_data) |data| {
        defer allocator.free(data);
        try parseIndexEntries(allocator, data, &entries);
    }

    const mtime_s: u32 = @intCast(stat.mtime.toSeconds());
    const mtime_ns: u32 = @intCast(@mod(stat.mtime.nanoseconds, std.time.ns_per_s));
    const new_entry = IndexEntry{
        .ctime_s = 0,
        .ctime_ns = 0,
        .mtime_s = mtime_s,
        .mtime_ns = mtime_ns,
        .dev = 0,
        .ino = 0,
        .mode = 0o100644,
        .uid = 0,
        .gid = 0,
        .size = @intCast(file_data.len),
        .sha1 = sha1,
        .flags = @intCast(rel_path.len & 0x0fff),
        .path = try allocator.dupe(u8, rel_path),
    };

    var replaced = false;
    for (entries.items) |*e| {
        if (std.mem.eql(u8, e.path, rel_path)) {
            e.deinit(allocator);
            e.* = new_entry;
            replaced = true;
            break;
        }
    }
    if (!replaced) {
        try entries.append(allocator, new_entry);
    }

    std.sort.pdq(IndexEntry, entries.items, {}, IndexEntry.lessThan);
    try writeIndex(allocator, io, index_path, entries.items);
}

pub fn removePathFromIndex(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo: BareRepository,
    rel_path: []const u8,
) !bool {
    const index_path = try std.fs.path.join(allocator, &.{ repo.path, "index" });
    defer allocator.free(index_path);

    const index_data = std.Io.Dir.cwd().readFileAlloc(io, index_path, allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer allocator.free(index_data);

    var entries = std.ArrayList(IndexEntry).empty;
    defer {
        for (entries.items) |e| e.deinit(allocator);
        entries.deinit(allocator);
    }
    try parseIndexEntries(allocator, index_data, &entries);

    var found = false;
    var i: usize = 0;
    while (i < entries.items.len) {
        if (std.mem.eql(u8, entries.items[i].path, rel_path)) {
            entries.items[i].deinit(allocator);
            _ = entries.swapRemove(i);
            found = true;
        } else {
            i += 1;
        }
    }

    if (!found) return false;

    std.sort.pdq(IndexEntry, entries.items, {}, IndexEntry.lessThan);
    try writeIndex(allocator, io, index_path, entries.items);
    return true;
}

// --- Item 10: create a commit from the current index ---

pub const CommitOptions = struct {
    message: []const u8,
    author_name: []const u8 = "desperta",
    author_email: []const u8 = "desperta@local",
};

pub fn createCommit(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo: BareRepository,
    opts: CommitOptions,
) !void {
    const index_path = try std.fs.path.join(allocator, &.{ repo.path, "index" });
    defer allocator.free(index_path);

    const index_data = std.Io.Dir.cwd().readFileAlloc(io, index_path, allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return Error.IndexMissing,
        else => return err,
    };
    defer allocator.free(index_data);

    var entries = std.ArrayList(IndexEntry).empty;
    defer {
        for (entries.items) |e| e.deinit(allocator);
        entries.deinit(allocator);
    }
    try parseIndexEntries(allocator, index_data, &entries);

    const tree_sha1 = try buildAndWriteTree(allocator, io, repo, entries.items, "");

    const parent_sha1 = try resolveHead(allocator, io, repo);
    defer if (parent_sha1) |p| allocator.free(p);

    const timestamp: i64 = std.time.timestamp();

    var commit_buf = std.Io.Writer.Allocating.init(allocator);
    defer commit_buf.deinit();

    const tree_hex = std.fmt.bytesToHex(tree_sha1, .lower);
    try commit_buf.writer.print("tree {s}\n", .{tree_hex});
    if (parent_sha1) |parent| {
        try commit_buf.writer.print("parent {s}\n", .{parent});
    }
    try commit_buf.writer.print("author {s} <{s}> {d} +0000\n", .{ opts.author_name, opts.author_email, timestamp });
    try commit_buf.writer.print("committer {s} <{s}> {d} +0000\n", .{ opts.author_name, opts.author_email, timestamp });
    try commit_buf.writer.print("\n{s}\n", .{opts.message});

    const commit_content = commit_buf.writer.buffered();

    var header_buf: [64]u8 = undefined;
    const header = try std.fmt.bufPrint(&header_buf, "commit {d}\x00", .{commit_content.len});

    const commit_sha1 = try writeGitObject(allocator, io, repo, header, commit_content);
    try updateRef(allocator, io, repo, commit_sha1);
}

// --- Internal helpers ---

pub fn parseHead(allocator: std.mem.Allocator, data: []const u8) !Head {
    const trimmed = std.mem.trim(u8, data, " \t\r\n");
    if (trimmed.len == 0) {
        return Error.InvalidHead;
    }

    if (std.mem.startsWith(u8, trimmed, "ref:")) {
        const ref_name = std.mem.trim(u8, trimmed["ref:".len..], " \t");
        const heads_prefix = "refs/heads/";
        if (!std.mem.startsWith(u8, ref_name, heads_prefix)) {
            return Error.UnsupportedHead;
        }

        const branch = ref_name[heads_prefix.len..];
        if (branch.len == 0) {
            return Error.InvalidHead;
        }

        return .{ .branch = try allocator.dupe(u8, branch) };
    }

    if (isObjectId(trimmed)) {
        return .{ .detached = try allocator.dupe(u8, trimmed) };
    }

    return Error.InvalidHead;
}

fn statusFromIndex(allocator: std.mem.Allocator, io: std.Io, data: []const u8, worktree_path: []const u8) !WorktreeStatus {
    if (data.len < 12 + 20) {
        return Error.InvalidIndex;
    }
    if (!std.mem.eql(u8, data[0..4], "DIRC")) {
        return Error.InvalidIndex;
    }

    const version = readBe32(data[4..8]);
    if (version != 2 and version != 3) {
        return Error.UnsupportedIndexVersion;
    }

    const entry_count = readBe32(data[8..12]);
    var offset: usize = 12;
    var status = WorktreeStatus{};

    var entry_index: u32 = 0;
    while (entry_index < entry_count) : (entry_index += 1) {
        if (offset + 62 > data.len - 20) {
            return Error.InvalidIndex;
        }

        const entry_start = offset;
        const mtime_seconds = readBe32(data[offset + 8 .. offset + 12]);
        // Item 5: read nanosecond precision for accurate dirty detection.
        const mtime_nanoseconds = readBe32(data[offset + 12 .. offset + 16]);
        const file_size = readBe32(data[offset + 36 .. offset + 40]);
        const flags = readBe16(data[offset + 60 .. offset + 62]);
        offset += 62;

        if ((flags & 0x4000) != 0) {
            if (version < 3 or offset + 2 > data.len - 20) {
                return Error.InvalidIndex;
            }
            offset += 2;
        }

        const name_len_flag = flags & 0x0fff;
        const path_start = offset;
        var path_end: usize = undefined;
        if (name_len_flag < 0x0fff) {
            path_end = path_start + name_len_flag;
            if (path_end >= data.len - 20 or data[path_end] != 0) {
                return Error.InvalidIndex;
            }
            offset = path_end + 1;
        } else {
            while (offset < data.len - 20 and data[offset] != 0) {
                offset += 1;
            }
            if (offset >= data.len - 20) {
                return Error.InvalidIndex;
            }
            path_end = offset;
            offset += 1;
        }

        const path = data[path_start..path_end];
        if (!isSafeIndexPath(path)) {
            return Error.InvalidIndex;
        }

        status.tracked += 1;
        try classifyIndexEntry(allocator, io, worktree_path, path, file_size, mtime_seconds, mtime_nanoseconds, &status);

        const entry_len = offset - entry_start;
        const padded_len = std.mem.alignForward(usize, entry_len, 8);
        offset = entry_start + padded_len;
    }

    if (offset > data.len - 20) {
        return Error.InvalidIndex;
    }

    return status;
}

// Item 5: compare mtime at nanosecond precision to avoid false negatives.
fn classifyIndexEntry(
    allocator: std.mem.Allocator,
    io: std.Io,
    worktree_path: []const u8,
    path: []const u8,
    index_size: u32,
    index_mtime_s: u32,
    index_mtime_ns: u32,
    status: *WorktreeStatus,
) !void {
    const full_path = try std.fs.path.join(allocator, &.{ worktree_path, path });
    defer allocator.free(full_path);

    const stat = std.Io.Dir.cwd().statFile(io, full_path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            status.deleted += 1;
            return;
        },
        else => return err,
    };

    if (stat.kind != .file) {
        status.modified += 1;
        return;
    }

    const expected_mtime: i96 = @as(i96, index_mtime_s) * std.time.ns_per_s + index_mtime_ns;
    if (stat.size != index_size or stat.mtime.nanoseconds != expected_mtime) {
        status.modified += 1;
        return;
    }

    status.clean += 1;
}

pub fn parseIndexEntries(allocator: std.mem.Allocator, data: []const u8, out: *std.ArrayList(IndexEntry)) !void {
    if (data.len < 12 + 20) return Error.InvalidIndex;
    if (!std.mem.eql(u8, data[0..4], "DIRC")) return Error.InvalidIndex;

    const version = readBe32(data[4..8]);
    if (version != 2 and version != 3) return Error.UnsupportedIndexVersion;

    const count = readBe32(data[8..12]);
    var offset: usize = 12;

    var i: u32 = 0;
    while (i < count) : (i += 1) {
        if (offset + 62 > data.len - 20) return Error.InvalidIndex;

        const entry_start = offset;
        var entry = IndexEntry{
            .ctime_s = readBe32(data[offset + 0 .. offset + 4]),
            .ctime_ns = readBe32(data[offset + 4 .. offset + 8]),
            .mtime_s = readBe32(data[offset + 8 .. offset + 12]),
            .mtime_ns = readBe32(data[offset + 12 .. offset + 16]),
            .dev = readBe32(data[offset + 16 .. offset + 20]),
            .ino = readBe32(data[offset + 20 .. offset + 24]),
            .mode = readBe32(data[offset + 24 .. offset + 28]),
            .uid = readBe32(data[offset + 28 .. offset + 32]),
            .gid = readBe32(data[offset + 32 .. offset + 36]),
            .size = readBe32(data[offset + 36 .. offset + 40]),
            .sha1 = data[offset + 40 .. offset + 60][0..20].*,
            .flags = readBe16(data[offset + 60 .. offset + 62]),
            .path = undefined,
        };
        offset += 62;

        if ((entry.flags & 0x4000) != 0) {
            if (version < 3 or offset + 2 > data.len - 20) return Error.InvalidIndex;
            offset += 2;
        }

        const name_len = entry.flags & 0x0fff;
        const path_start = offset;
        var path_end: usize = undefined;
        if (name_len < 0x0fff) {
            path_end = path_start + name_len;
            if (path_end >= data.len - 20 or data[path_end] != 0) return Error.InvalidIndex;
            offset = path_end + 1;
        } else {
            while (offset < data.len - 20 and data[offset] != 0) offset += 1;
            if (offset >= data.len - 20) return Error.InvalidIndex;
            path_end = offset;
            offset += 1;
        }

        const path_slice = data[path_start..path_end];
        if (!isSafeIndexPath(path_slice)) return Error.InvalidIndex;

        entry.path = try allocator.dupe(u8, path_slice);
        errdefer allocator.free(entry.path);
        try out.append(allocator, entry);

        const entry_len = offset - entry_start;
        const padded = std.mem.alignForward(usize, entry_len, 8);
        offset = entry_start + padded;
    }
}

fn writeIndex(allocator: std.mem.Allocator, io: std.Io, path: []const u8, entries: []const IndexEntry) !void {
    var buf = std.Io.Writer.Allocating.init(allocator);
    defer buf.deinit();

    try buf.writer.writeAll("DIRC");
    try writeBe32(&buf.writer, 2);
    try writeBe32(&buf.writer, @intCast(entries.len));

    for (entries) |e| {
        try writeBe32(&buf.writer, e.ctime_s);
        try writeBe32(&buf.writer, e.ctime_ns);
        try writeBe32(&buf.writer, e.mtime_s);
        try writeBe32(&buf.writer, e.mtime_ns);
        try writeBe32(&buf.writer, e.dev);
        try writeBe32(&buf.writer, e.ino);
        try writeBe32(&buf.writer, e.mode);
        try writeBe32(&buf.writer, e.uid);
        try writeBe32(&buf.writer, e.gid);
        try writeBe32(&buf.writer, e.size);
        try buf.writer.writeAll(&e.sha1);
        try writeBe16(&buf.writer, @intCast(e.path.len & 0x0fff));
        try buf.writer.writeAll(e.path);
        try buf.writer.writeByte(0);

        // Pad entry to 8-byte alignment (62 fixed bytes + path + NUL).
        const entry_len = 62 + e.path.len + 1;
        const padded = std.mem.alignForward(usize, entry_len, 8);
        const pad_needed = padded - entry_len;
        var k: usize = 0;
        while (k < pad_needed) : (k += 1) try buf.writer.writeByte(0);
    }

    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(buf.writer.buffered());
    var digest: [20]u8 = undefined;
    hasher.final(&digest);
    try buf.writer.writeAll(&digest);

    if (std.fs.path.dirname(path)) |dir| {
        try std.Io.Dir.cwd().createDirPath(io, dir);
    }
    var file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);
    try file.writePositionalAll(io, buf.writer.buffered(), 0);
}

fn writeBlobObject(allocator: std.mem.Allocator, io: std.Io, repo: BareRepository, content: []const u8) ![20]u8 {
    var header_buf: [32]u8 = undefined;
    const header = try std.fmt.bufPrint(&header_buf, "blob {d}\x00", .{content.len});
    return writeGitObject(allocator, io, repo, header, content);
}

fn buildAndWriteTree(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo: BareRepository,
    entries: []const IndexEntry,
    prefix: []const u8,
) ![20]u8 {
    var tree_buf = std.Io.Writer.Allocating.init(allocator);
    defer tree_buf.deinit();

    var seen = std.StringHashMap(void).init(allocator);
    defer seen.deinit();

    for (entries) |e| {
        // Skip entries that don't belong to this prefix level.
        if (prefix.len > 0 and !std.mem.startsWith(u8, e.path, prefix)) continue;
        const rel = if (prefix.len == 0) e.path else e.path[prefix.len..];

        const slash = std.mem.indexOfScalar(u8, rel, '/');
        if (slash == null) {
            // Direct file: emit blob entry.
            try tree_buf.writer.print("100644 {s}\x00", .{rel});
            try tree_buf.writer.writeAll(&e.sha1);
        } else {
            // Sub-directory: emit once per unique top-level component.
            const dir_name = rel[0..slash.?];
            if (seen.contains(dir_name)) continue;
            try seen.put(dir_name, {});

            const sub_prefix = try std.fmt.allocPrint(allocator, "{s}{s}/", .{ prefix, dir_name });
            defer allocator.free(sub_prefix);

            const sub_sha1 = try buildAndWriteTree(allocator, io, repo, entries, sub_prefix);
            try tree_buf.writer.print("40000 {s}\x00", .{dir_name});
            try tree_buf.writer.writeAll(&sub_sha1);
        }
    }

    const tree_content = tree_buf.writer.buffered();
    var header_buf: [32]u8 = undefined;
    const header = try std.fmt.bufPrint(&header_buf, "tree {d}\x00", .{tree_content.len});
    return writeGitObject(allocator, io, repo, header, tree_content);
}

fn writeGitObject(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo: BareRepository,
    header: []const u8,
    content: []const u8,
) ![20]u8 {
    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(header);
    hasher.update(content);
    var sha1: [20]u8 = undefined;
    hasher.final(&sha1);

    const hex = std.fmt.bytesToHex(sha1, .lower);

    const obj_dir = try std.fmt.allocPrint(allocator, "{s}/objects/{s}", .{ repo.path, hex[0..2] });
    defer allocator.free(obj_dir);
    try std.Io.Dir.cwd().createDirPath(io, obj_dir);

    const obj_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ obj_dir, hex[2..] });
    defer allocator.free(obj_path);

    if (exists(io, obj_path)) return sha1;

    const compressed = try zlibCompress(allocator, header, content);
    defer allocator.free(compressed);

    var file = try std.Io.Dir.cwd().createFile(io, obj_path, .{});
    defer file.close(io);
    try file.writePositionalAll(io, compressed, 0);

    return sha1;
}

fn zlibCompress(allocator: std.mem.Allocator, header: []const u8, content: []const u8) ![]u8 {
    var out = try std.Io.Writer.Allocating.initCapacity(allocator, 4096);
    defer out.deinit();

    var comp_buf: [65536]u8 = undefined;
    var compressor = try std.compress.flate.Compress.Huffman.init(&out.writer, &comp_buf, .zlib);
    try compressor.writer.writeAll(header);
    try compressor.writer.writeAll(content);
    try compressor.writer.flush();

    return allocator.dupe(u8, out.writer.buffered());
}

fn resolveHead(allocator: std.mem.Allocator, io: std.Io, repo: BareRepository) !?[]const u8 {
    const ref_path = switch (repo.head) {
        .branch => |branch| try std.fmt.allocPrint(allocator, "{s}/refs/heads/{s}", .{ repo.path, branch }),
        .detached => |oid| return try allocator.dupe(u8, oid),
    };
    defer allocator.free(ref_path);

    const ref_data = std.Io.Dir.cwd().readFileAlloc(io, ref_path, allocator, .limited(64)) catch |err| switch (err) {
        error.FileNotFound => return null,
        else => return err,
    };
    defer allocator.free(ref_data);

    const oid = std.mem.trim(u8, ref_data, " \t\r\n");
    if (!isObjectId(oid)) return null;
    return try allocator.dupe(u8, oid);
}

fn updateRef(allocator: std.mem.Allocator, io: std.Io, repo: BareRepository, sha1: [20]u8) !void {
    const branch = switch (repo.head) {
        .branch => |b| b,
        .detached => return error.DetachedHead,
    };

    const ref_path = try std.fmt.allocPrint(allocator, "{s}/refs/heads/{s}", .{ repo.path, branch });
    defer allocator.free(ref_path);

    if (std.fs.path.dirname(ref_path)) |dir| {
        try std.Io.Dir.cwd().createDirPath(io, dir);
    }

    const hex = std.fmt.bytesToHex(sha1, .lower);
    var hex_buf: [41]u8 = undefined;
    const hex_str = try std.fmt.bufPrint(&hex_buf, "{s}\n", .{hex});

    var file = try std.Io.Dir.cwd().createFile(io, ref_path, .{});
    defer file.close(io);
    try file.writePositionalAll(io, hex_str, 0);
}

fn requireGitDir(allocator: std.mem.Allocator, io: std.Io, repo_path: []const u8) !void {
    if (!exists(io, repo_path)) {
        return Error.NotGitRepository;
    }

    const objects_path = try std.fs.path.join(allocator, &.{ repo_path, "objects" });
    defer allocator.free(objects_path);
    const refs_path = try std.fs.path.join(allocator, &.{ repo_path, "refs" });
    defer allocator.free(refs_path);

    if (!exists(io, objects_path) or !exists(io, refs_path)) {
        return Error.NotBareRepository;
    }

    const config_path = try std.fs.path.join(allocator, &.{ repo_path, "config" });
    defer allocator.free(config_path);

    const config_data = std.Io.Dir.cwd().readFileAlloc(io, config_path, allocator, .limited(1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return Error.NotBareRepository,
        else => return err,
    };
    defer allocator.free(config_data);

    if (!configHasBareTrue(config_data)) {
        return Error.NotBareRepository;
    }
}

// Item 8 refactor: use std.mem.readInt instead of manual bit-shifting.
fn readBe16(bytes: []const u8) u16 {
    return std.mem.readInt(u16, bytes[0..2], .big);
}

fn readBe32(bytes: []const u8) u32 {
    return std.mem.readInt(u32, bytes[0..4], .big);
}

fn writeBe16(w: *std.Io.Writer, value: u16) !void {
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, value, .big);
    try w.writeAll(&bytes);
}

fn writeBe32(w: *std.Io.Writer, value: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .big);
    try w.writeAll(&bytes);
}

fn exists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn isObjectId(value: []const u8) bool {
    if (value.len != 40 and value.len != 64) {
        return false;
    }

    for (value) |char| {
        if (!std.ascii.isHex(char)) {
            return false;
        }
    }

    return true;
}

pub fn isSafeIndexPath(path: []const u8) bool {
    if (path.len == 0 or std.fs.path.isAbsolute(path)) {
        return false;
    }

    var parts = std.mem.splitScalar(u8, path, '/');
    while (parts.next()) |part| {
        if (part.len == 0 or std.mem.eql(u8, part, ".") or std.mem.eql(u8, part, "..")) {
            return false;
        }
    }

    return true;
}

fn configHasBareTrue(data: []const u8) bool {
    var in_core = false;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#' or trimmed[0] == ';') {
            continue;
        }

        if (trimmed[0] == '[') {
            in_core = std.mem.eql(u8, trimmed, "[core]");
            continue;
        }

        if (!in_core) {
            continue;
        }

        if (std.mem.indexOfScalar(u8, trimmed, '=')) |eq_index| {
            const key = std.mem.trim(u8, trimmed[0..eq_index], " \t");
            const value = std.mem.trim(u8, trimmed[eq_index + 1 ..], " \t");
            if (std.mem.eql(u8, key, "bare") and std.mem.eql(u8, value, "true")) {
                return true;
            }
        }
    }

    return false;
}

// --- Tests ---

test "parse branch HEAD" {
    var head = try parseHead(std.testing.allocator, "ref: refs/heads/main\n");
    defer head.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("main", head.branch);
}

test "parse detached HEAD" {
    var head = try parseHead(std.testing.allocator, "0123456789abcdef0123456789abcdef01234567\n");
    defer head.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("0123456789abcdef0123456789abcdef01234567", head.detached);
}

test "open bare repository metadata" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const io = std.testing.io;
    try tmp.dir.createDirPath(io, "repo.git/objects");
    try tmp.dir.createDirPath(io, "repo.git/refs/heads");
    try tmp.dir.writeFile(io, .{ .sub_path = "repo.git/HEAD", .data = "ref: refs/heads/base\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "repo.git/config", .data = "[core]\n\tbare = true\n" });

    const repo_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/repo.git", .{tmp.sub_path});
    defer std.testing.allocator.free(repo_path);

    var repo = try openBare(std.testing.allocator, io, repo_path);
    defer repo.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings(repo_path, repo.path);
    try std.testing.expectEqualStrings("base", repo.head.branch);
}

test "reject non-bare repository metadata" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const io = std.testing.io;
    try tmp.dir.createDirPath(io, "repo/.git/objects");
    try tmp.dir.createDirPath(io, "repo/.git/refs/heads");
    try tmp.dir.writeFile(io, .{ .sub_path = "repo/.git/HEAD", .data = "ref: refs/heads/main\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "repo/.git/config", .data = "[core]\n\tbare = false\n" });

    const repo_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/repo/.git", .{tmp.sub_path});
    defer std.testing.allocator.free(repo_path);

    try std.testing.expectError(error.NotBareRepository, openBare(std.testing.allocator, io, repo_path));
}

test "worktree status classifies index entries by stat metadata" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const io = std.testing.io;
    try tmp.dir.createDirPath(io, "repo.git/objects");
    try tmp.dir.createDirPath(io, "repo.git/refs/heads");
    try tmp.dir.writeFile(io, .{ .sub_path = "repo.git/HEAD", .data = "ref: refs/heads/main\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "repo.git/config", .data = "[core]\n\tbare = true\n" });
    try tmp.dir.createDirPath(io, "work");
    try tmp.dir.writeFile(io, .{ .sub_path = "work/clean.txt", .data = "abc" });
    try tmp.dir.writeFile(io, .{ .sub_path = "work/modified.txt", .data = "abcd" });

    const clean_stat = try tmp.dir.statFile(io, "work/clean.txt", .{});
    const modified_stat = try tmp.dir.statFile(io, "work/modified.txt", .{});
    // Item 5: capture full nanosecond precision so clean detection is accurate.
    const clean_mtime_s: u32 = @intCast(clean_stat.mtime.toSeconds());
    const clean_mtime_ns: u32 = @intCast(@mod(clean_stat.mtime.nanoseconds, std.time.ns_per_s));
    const modified_mtime_s: u32 = @intCast(modified_stat.mtime.toSeconds());
    const modified_mtime_ns: u32 = @intCast(@mod(modified_stat.mtime.nanoseconds, std.time.ns_per_s));

    const index_data = try makeTestIndex(std.testing.allocator, &.{
        .{ .path = "clean.txt", .mtime_s = clean_mtime_s, .mtime_ns = clean_mtime_ns, .size = 3 },
        .{ .path = "modified.txt", .mtime_s = modified_mtime_s, .mtime_ns = modified_mtime_ns, .size = 3 },
        .{ .path = "deleted.txt", .mtime_s = clean_mtime_s, .mtime_ns = clean_mtime_ns, .size = 7 },
    });
    defer std.testing.allocator.free(index_data);
    try tmp.dir.writeFile(io, .{ .sub_path = "repo.git/index", .data = index_data });

    const repo_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/repo.git", .{tmp.sub_path});
    defer std.testing.allocator.free(repo_path);
    const worktree_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/work", .{tmp.sub_path});
    defer std.testing.allocator.free(worktree_path);

    var repo = try openBare(std.testing.allocator, io, repo_path);
    defer repo.deinit(std.testing.allocator);

    const status = try statusWorktree(std.testing.allocator, io, repo, worktree_path);
    try std.testing.expectEqual(@as(u32, 3), status.tracked);
    try std.testing.expectEqual(@as(u32, 1), status.clean);
    try std.testing.expectEqual(@as(u32, 1), status.modified);
    try std.testing.expectEqual(@as(u32, 1), status.deleted);
    try std.testing.expectEqual(@as(u32, 2), status.dirty());
}

test "addPathToIndex stages a file and round-trips through statusWorktree" {
    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();

    const io = std.testing.io;
    try tmp.dir.createDirPath(io, "repo.git/objects/info");
    try tmp.dir.createDirPath(io, "repo.git/objects/pack");
    try tmp.dir.createDirPath(io, "repo.git/refs/heads");
    try tmp.dir.writeFile(io, .{ .sub_path = "repo.git/HEAD", .data = "ref: refs/heads/main\n" });
    try tmp.dir.writeFile(io, .{ .sub_path = "repo.git/config", .data = "[core]\n\tbare = true\n" });
    try tmp.dir.createDirPath(io, "work");
    try tmp.dir.writeFile(io, .{ .sub_path = "work/hello.txt", .data = "hello world\n" });

    const repo_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/repo.git", .{tmp.sub_path});
    defer std.testing.allocator.free(repo_path);
    const work_path = try std.fmt.allocPrint(std.testing.allocator, ".zig-cache/tmp/{s}/work", .{tmp.sub_path});
    defer std.testing.allocator.free(work_path);

    var repo = try openBare(std.testing.allocator, io, repo_path);
    defer repo.deinit(std.testing.allocator);

    try addPathToIndex(std.testing.allocator, io, repo, work_path, "hello.txt");

    const status = try statusWorktree(std.testing.allocator, io, repo, work_path);
    try std.testing.expectEqual(@as(u32, 1), status.tracked);
    try std.testing.expectEqual(@as(u32, 1), status.clean);
    try std.testing.expectEqual(@as(u32, 0), status.modified);
}

// --- Test helpers ---

const TestIndexEntry = struct {
    path: []const u8,
    mtime_s: u32,
    mtime_ns: u32 = 0,
    size: u32,
};

fn makeTestIndex(allocator: std.mem.Allocator, entries: []const TestIndexEntry) ![]u8 {
    var data: std.ArrayList(u8) = .empty;
    errdefer data.deinit(allocator);

    try data.appendSlice(allocator, "DIRC");
    try appendBe32(&data, allocator, 2);
    try appendBe32(&data, allocator, @intCast(entries.len));

    for (entries) |entry| {
        const entry_start = data.items.len;
        try appendBe32(&data, allocator, 0); // ctime_s
        try appendBe32(&data, allocator, 0); // ctime_ns
        try appendBe32(&data, allocator, entry.mtime_s);
        try appendBe32(&data, allocator, entry.mtime_ns);
        try appendBe32(&data, allocator, 0); // dev
        try appendBe32(&data, allocator, 0); // ino
        try appendBe32(&data, allocator, 0o100644); // mode
        try appendBe32(&data, allocator, 0); // uid
        try appendBe32(&data, allocator, 0); // gid
        try appendBe32(&data, allocator, entry.size);
        try data.appendNTimes(allocator, 0, 20); // sha1
        try appendBe16(&data, allocator, @intCast(entry.path.len));
        try data.appendSlice(allocator, entry.path);
        try data.append(allocator, 0);

        while ((data.items.len - entry_start) % 8 != 0) {
            try data.append(allocator, 0);
        }
    }

    var hasher = std.crypto.hash.Sha1.init(.{});
    hasher.update(data.items);
    var digest: [20]u8 = undefined;
    hasher.final(&digest);
    try data.appendSlice(allocator, &digest);

    return data.toOwnedSlice(allocator);
}

fn appendBe16(data: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u16) !void {
    var bytes: [2]u8 = undefined;
    std.mem.writeInt(u16, &bytes, value, .big);
    try data.appendSlice(allocator, &bytes);
}

fn appendBe32(data: *std.ArrayList(u8), allocator: std.mem.Allocator, value: u32) !void {
    var bytes: [4]u8 = undefined;
    std.mem.writeInt(u32, &bytes, value, .big);
    try data.appendSlice(allocator, &bytes);
}
