const std = @import("std");

pub const Mapping = struct {
    src: []const u8,
    dst: []const u8,
};

pub const DeployResult = struct {
    deployed: u32,
    skipped: u32,
    tracked: [][]const u8,

    pub fn deinit(self: *DeployResult, allocator: std.mem.Allocator) void {
        for (self.tracked) |p| allocator.free(p);
        allocator.free(self.tracked);
    }
};

// Returns the template dir to use: dotfiles/<host>/ if it exists, otherwise dotfiles/default/
pub fn resolveTemplateDir(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo_dir: []const u8,
    from_host: ?[]const u8,
) ![]const u8 {
    if (from_host) |host| {
        const candidate = try std.fmt.allocPrint(allocator, "{s}/dotfiles/{s}", .{ repo_dir, host });
        std.Io.Dir.cwd().access(io, candidate, .{}) catch {
            allocator.free(candidate);
            return try std.fmt.allocPrint(allocator, "{s}/dotfiles/default", .{repo_dir});
        };
        return candidate;
    }
    return try std.fmt.allocPrint(allocator, "{s}/dotfiles/default", .{repo_dir});
}

// Deploy template_dir/home/* → home/ and template_dir/config/* → xdg_config_home/
// By default, existing files at the destination are skipped (preserving user edits).
// Pass force=true to overwrite.
pub fn deploy(
    io: std.Io,
    allocator: std.mem.Allocator,
    home: []const u8,
    xdg_config_home: []const u8,
    template_dir: []const u8,
    dry_run: bool,
    force: bool,
    out: *std.Io.Writer,
) !DeployResult {
    var tracked = std.ArrayList([]const u8).empty;
    errdefer {
        for (tracked.items) |p| allocator.free(p);
        tracked.deinit(allocator);
    }

    var deployed: u32 = 0;
    var skipped: u32 = 0;

    const home_src = try std.fmt.allocPrint(allocator, "{s}/home", .{template_dir});
    defer allocator.free(home_src);
    try deployTree(io, allocator, home_src, home, dry_run, force, out, &tracked, &deployed, &skipped);

    const config_src = try std.fmt.allocPrint(allocator, "{s}/config", .{template_dir});
    defer allocator.free(config_src);
    try deployTree(io, allocator, config_src, xdg_config_home, dry_run, force, out, &tracked, &deployed, &skipped);

    return .{
        .deployed = deployed,
        .skipped = skipped,
        .tracked = try tracked.toOwnedSlice(allocator),
    };
}

fn deployTree(
    io: std.Io,
    allocator: std.mem.Allocator,
    src_root: []const u8,
    dst_root: []const u8,
    dry_run: bool,
    force: bool,
    out: *std.Io.Writer,
    tracked: *std.ArrayList([]const u8),
    deployed: *u32,
    skipped: *u32,
) !void {
    var src_dir = std.Io.Dir.cwd().openDir(io, src_root, .{ .iterate = true }) catch |err| switch (err) {
        error.FileNotFound, error.NotDir => return,
        else => return err,
    };
    defer src_dir.close(io);

    var walker = try src_dir.walk(allocator);
    defer walker.deinit();

    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;

        const rel = entry.path;
        const src_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ src_root, rel });
        defer allocator.free(src_path);
        const dst_path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ dst_root, rel });
        defer allocator.free(dst_path);

        const exists = blk: {
            std.Io.Dir.cwd().access(io, dst_path, .{}) catch break :blk false;
            break :blk true;
        };

        if (exists and !force) {
            try out.print("  skip (exists): {s}\n", .{dst_path});
            skipped.* += 1;
            const tracked_path = try allocator.dupe(u8, dst_path);
            try tracked.append(allocator, tracked_path);
            continue;
        }

        try out.print("  deploy: {s}\n", .{dst_path});
        if (!dry_run) {
            try copyFile(io, allocator, src_path, dst_path);
        }
        const tracked_path = try allocator.dupe(u8, dst_path);
        try tracked.append(allocator, tracked_path);
        deployed.* += 1;
    }
}

fn copyFile(
    io: std.Io,
    allocator: std.mem.Allocator,
    src: []const u8,
    dst: []const u8,
) !void {
    // Ensure parent directory exists
    if (std.fs.path.dirname(dst)) |parent| {
        std.Io.Dir.cwd().createDirPath(io, parent) catch |err| switch (err) {
            error.PathAlreadyExists => {},
            else => return err,
        };
    }

    const data = try std.Io.Dir.cwd().readFileAlloc(io, src, allocator, .limited(4 * 1024 * 1024));
    defer allocator.free(data);

    const file = try std.Io.Dir.cwd().createFile(io, dst, .{ .truncate = true });
    defer file.close(io);
    try file.writePositionalAll(io, data, 0);
}

test "resolveTemplateDir returns default when host dir not found" {
    const io = std.Io.null_io;
    const dir = try resolveTemplateDir(std.testing.allocator, io, "/nonexistent", "testhost");
    defer std.testing.allocator.free(dir);
    try std.testing.expectEqualStrings("/nonexistent/dotfiles/default", dir);
}

test "resolveTemplateDir returns default when from_host is null" {
    const io = std.Io.null_io;
    const dir = try resolveTemplateDir(std.testing.allocator, io, "/repo", null);
    defer std.testing.allocator.free(dir);
    try std.testing.expectEqualStrings("/repo/dotfiles/default", dir);
}
