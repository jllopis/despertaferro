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
        try classifyIndexEntry(allocator, io, worktree_path, path, file_size, mtime_seconds, &status);

        const entry_len = offset - entry_start;
        const padded_len = std.mem.alignForward(usize, entry_len, 8);
        offset = entry_start + padded_len;
    }

    if (offset > data.len - 20) {
        return Error.InvalidIndex;
    }

    return status;
}

fn classifyIndexEntry(
    allocator: std.mem.Allocator,
    io: std.Io,
    worktree_path: []const u8,
    path: []const u8,
    index_size: u32,
    index_mtime_seconds: u32,
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

    const stat_mtime_seconds: u64 = @intCast(stat.mtime.toSeconds());
    if (stat.size != index_size or stat_mtime_seconds != index_mtime_seconds) {
        status.modified += 1;
        return;
    }

    status.clean += 1;
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

fn readBe16(bytes: []const u8) u16 {
    return (@as(u16, bytes[0]) << 8) | bytes[1];
}

fn readBe32(bytes: []const u8) u32 {
    return (@as(u32, bytes[0]) << 24) |
        (@as(u32, bytes[1]) << 16) |
        (@as(u32, bytes[2]) << 8) |
        bytes[3];
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

fn isSafeIndexPath(path: []const u8) bool {
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
    const clean_mtime_seconds: u32 = @intCast(clean_stat.mtime.toSeconds());
    const modified_mtime_seconds: u32 = @intCast(modified_stat.mtime.toSeconds());

    const index_data = try makeTestIndex(std.testing.allocator, &.{
        .{ .path = "clean.txt", .mtime_seconds = clean_mtime_seconds, .size = 3 },
        .{ .path = "modified.txt", .mtime_seconds = modified_mtime_seconds, .size = 3 },
        .{ .path = "deleted.txt", .mtime_seconds = clean_mtime_seconds, .size = 7 },
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

const TestIndexEntry = struct {
    path: []const u8,
    mtime_seconds: u32,
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
        try appendBe32(&data, allocator, 0);
        try appendBe32(&data, allocator, 0);
        try appendBe32(&data, allocator, entry.mtime_seconds);
        try appendBe32(&data, allocator, 0);
        try appendBe32(&data, allocator, 0);
        try appendBe32(&data, allocator, 0);
        try appendBe32(&data, allocator, 0o100644);
        try appendBe32(&data, allocator, 0);
        try appendBe32(&data, allocator, 0);
        try appendBe32(&data, allocator, entry.size);
        try data.appendNTimes(allocator, 0, 20);
        try appendBe16(&data, allocator, @intCast(entry.path.len));
        try data.appendSlice(allocator, entry.path);
        try data.append(allocator, 0);

        while ((data.items.len - entry_start) % 8 != 0) {
            try data.append(allocator, 0);
        }
    }

    try data.appendNTimes(allocator, 0, 20);
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
