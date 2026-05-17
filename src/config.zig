const std = @import("std");

pub const Config = struct {
    repo_path: ?[]const u8 = null,
    worktree: ?[]const u8 = null,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.repo_path) |p| allocator.free(p);
        if (self.worktree) |p| allocator.free(p);
        self.* = .{};
    }
};

pub fn configPath(allocator: std.mem.Allocator, environ_map: *const std.process.Environ.Map) ![]const u8 {
    if (environ_map.get("XDG_CONFIG_HOME")) |xdg| {
        return std.fmt.allocPrint(allocator, "{s}/despertaferro/config.toml", .{xdg});
    }
    if (environ_map.get("HOME")) |home| {
        return std.fmt.allocPrint(allocator, "{s}/.config/despertaferro/config.toml", .{home});
    }
    return error.MissingHome;
}

pub fn load(allocator: std.mem.Allocator, io: std.Io, environ_map: *const std.process.Environ.Map) !Config {
    const path = try configPath(allocator, environ_map);
    defer allocator.free(path);

    const data = std.Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(64 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer allocator.free(data);
    return parse(allocator, data);
}

fn parse(allocator: std.mem.Allocator, data: []const u8) !Config {
    var cfg: Config = .{};
    errdefer cfg.deinit(allocator);

    var in_runtime = false;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (trimmed[0] == '[') {
            in_runtime = std.mem.eql(u8, trimmed, "[runtime]");
            continue;
        }
        if (!in_runtime) continue;

        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const key = std.mem.trim(u8, trimmed[0..eq], " \t");
        var val = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
        if (val.len >= 2 and val[0] == '"' and val[val.len - 1] == '"') {
            val = val[1 .. val.len - 1];
        }

        if (std.mem.eql(u8, key, "repo_path")) {
            if (cfg.repo_path) |old| allocator.free(old);
            cfg.repo_path = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "work_tree")) {
            if (cfg.worktree) |old| allocator.free(old);
            cfg.worktree = try allocator.dupe(u8, val);
        }
    }

    return cfg;
}

test "parse runtime config" {
    const data =
        \\[runtime]
        \\repo_path = "/home/user/.local/state/despertaferro/repo.git"
        \\work_tree = "/home/user"
        \\
        \\[other]
        \\ignored = "yes"
    ;
    var cfg = try parse(std.testing.allocator, data);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("/home/user/.local/state/despertaferro/repo.git", cfg.repo_path.?);
    try std.testing.expectEqualStrings("/home/user", cfg.worktree.?);
}

test "missing config returns empty" {
    var cfg = try parse(std.testing.allocator, "");
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expect(cfg.repo_path == null);
    try std.testing.expect(cfg.worktree == null);
}
