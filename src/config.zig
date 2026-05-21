const std = @import("std");

pub const Config = struct {
    repo_path: ?[]const u8 = null,
    worktree: ?[]const u8 = null,
    project_dir: ?[]const u8 = null,

    pub fn deinit(self: *Config, allocator: std.mem.Allocator) void {
        if (self.repo_path) |p| allocator.free(p);
        if (self.worktree) |p| allocator.free(p);
        if (self.project_dir) |p| allocator.free(p);
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
        } else if (std.mem.eql(u8, key, "project_dir")) {
            if (cfg.project_dir) |old| allocator.free(old);
            cfg.project_dir = try allocator.dupe(u8, val);
        }
    }

    return cfg;
}

test "parse runtime config" {
    const data =
        \\[runtime]
        \\repo_path = "/home/user/.local/state/despertaferro/repo.git"
        \\work_tree = "/home/user"
        \\project_dir = "/home/user/.local/share/despertaferro"
        \\
        \\[other]
        \\ignored = "yes"
    ;
    var cfg = try parse(std.testing.allocator, data);
    defer cfg.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("/home/user/.local/state/despertaferro/repo.git", cfg.repo_path.?);
    try std.testing.expectEqualStrings("/home/user", cfg.worktree.?);
    try std.testing.expectEqualStrings("/home/user/.local/share/despertaferro", cfg.project_dir.?);
}

test "missing config returns empty" {
    var cfg = try parse(std.testing.allocator, "");
    defer cfg.deinit(std.testing.allocator);
    try std.testing.expect(cfg.repo_path == null);
    try std.testing.expect(cfg.worktree == null);
}

/// Resolve project directory with cascading resolution:
/// 1. Explicit flag `--repo <path>`
/// 2. Environment variable `DESPERTA_REPO`
/// 3. Config file `project_dir` field
/// 4. Fallback: walk up from cwd looking for `desperta.toml`
/// 5. Error if none found
pub fn resolveProjectDir(
    allocator: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
    cfg: *const Config,
    flag_repo: ?[]const u8,
) ![]const u8 {
    // 1. Explicit flag takes highest priority
    if (flag_repo) |path| {
        return allocator.dupe(u8, path);
    }

    // 2. Environment variable
    if (environ_map.get("DESPERTA_REPO")) |path| {
        return allocator.dupe(u8, path);
    }

    // 3. Config file
    if (cfg.project_dir) |path| {
        return allocator.dupe(u8, path);
    }

    // 4. Fallback: walk up from cwd looking for desperta.toml
    var arena = std.heap.ArenaAllocator.init(allocator);
    defer arena.deinit();

    const cwd = try std.fs.cwd().realpathAlloc(arena.allocator(), ".");

    var path = cwd;
    while (true) {
        const manifest_path = try std.fmt.allocPrint(arena.allocator(), "{s}/desperta.toml", .{path});
        if (std.fs.cwd().access(manifest_path, .{})) {
            return allocator.dupe(u8, path);
        } else |_| {}

        const parent = std.fs.path.dirname(path);
        if (parent == null or std.mem.eql(u8, parent.?, path)) {
            break; // reached root
        }
        path = parent.?;
    }

    // 5. Not found
    return error.ProjectDirNotFound;
}
