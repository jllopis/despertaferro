const std = @import("std");

pub const Error = error{
    InvalidHead,
    NotBareRepository,
    NotGitRepository,
    UnsupportedHead,
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
