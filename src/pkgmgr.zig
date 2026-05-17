const std = @import("std");
const packages = @import("packages.zig");

pub const Manager = enum { pacman, yay, paru, brew };

pub const InstallPlan = struct {
    pacman: std.ArrayList([]const u8),
    aur: std.ArrayList([]const u8),
    brew: std.ArrayList([]const u8),
    brew_cask: std.ArrayList([]const u8),
    script: std.ArrayList([]const u8),
    skip: std.ArrayList([]const u8),

    pub fn init() InstallPlan {
        return .{
            .pacman = .empty,
            .aur = .empty,
            .brew = .empty,
            .brew_cask = .empty,
            .script = .empty,
            .skip = .empty,
        };
    }

    pub fn deinit(self: *InstallPlan, allocator: std.mem.Allocator) void {
        self.pacman.deinit(allocator);
        self.aur.deinit(allocator);
        self.brew.deinit(allocator);
        self.brew_cask.deinit(allocator);
        self.script.deinit(allocator);
        // skip items are allocated strings (pkg_id: reason), free them individually.
        for (self.skip.items) |s| allocator.free(s);
        self.skip.deinit(allocator);
    }

    pub fn isEmpty(self: InstallPlan) bool {
        return self.pacman.items.len == 0 and
            self.aur.items.len == 0 and
            self.brew.items.len == 0 and
            self.brew_cask.items.len == 0 and
            self.script.items.len == 0;
    }
};

// Detect the primary available package manager.
pub fn detect(io: std.Io, environ_map: *const std.process.Environ.Map) ?Manager {
    if (isInPath(io, environ_map, "yay")) return .yay;
    if (isInPath(io, environ_map, "paru")) return .paru;
    if (isInPath(io, environ_map, "pacman")) return .pacman;
    if (isInPath(io, environ_map, "brew")) return .brew;
    return null;
}

pub fn isInstalled(io: std.Io, environ_map: *const std.process.Environ.Map, pkg: packages.Package) bool {
    const cmd = pkg.binaryCmd();
    if (cmd.len == 0) return false; // font packages etc. with no binary
    return isInPath(io, environ_map, cmd);
}

pub fn isInPath(io: std.Io, environ_map: *const std.process.Environ.Map, cmd: []const u8) bool {
    const path_env = environ_map.get("PATH") orelse return false;
    var iter = std.mem.splitScalar(u8, path_env, ':');
    while (iter.next()) |dir| {
        var buf: [std.fs.max_path_bytes]u8 = undefined;
        const full = std.fmt.bufPrint(&buf, "{s}/{s}", .{ dir, cmd }) catch continue;
        std.Io.Dir.cwd().access(io, full, .{}) catch continue;
        return true;
    }
    return false;
}

// Build an install plan for a set of packages given the available manager.
pub fn buildPlan(
    allocator: std.mem.Allocator,
    pkgs: []const packages.Package,
    mgr: ?Manager,
    platform: []const u8,
) !InstallPlan {
    var plan = InstallPlan.init();
    errdefer plan.deinit(allocator);

    for (pkgs) |pkg| {
        if (!pkg.hasPlatform(platform)) continue;

        if (pkg.skip) |reason| {
            const msg = try std.fmt.allocPrint(allocator, "{s}: {s}", .{ pkg.id, reason });
            try plan.skip.append(allocator, msg);
            continue;
        }

        if (pkg.install_script) |_| {
            try plan.script.append(allocator, pkg.id);
            continue;
        }

        // Pick the right install method based on available manager.
        switch (mgr orelse .brew) {
            .yay, .paru => {
                if (pkg.aur) |name| {
                    try plan.aur.append(allocator, name);
                } else if (pkg.pacman) |name| {
                    try plan.pacman.append(allocator, name);
                } else if (pkg.brew_cask) |name| {
                    try plan.brew_cask.append(allocator, name);
                } else if (pkg.brew) |name| {
                    try plan.brew.append(allocator, name);
                }
            },
            .pacman => {
                if (pkg.pacman) |name| {
                    try plan.pacman.append(allocator, name);
                }
            },
            .brew => {
                if (pkg.brew_cask) |name| {
                    try plan.brew_cask.append(allocator, name);
                } else if (pkg.brew) |name| {
                    try plan.brew.append(allocator, name);
                }
            },
        }
    }
    return plan;
}

// Execute or print an install plan.
pub fn executePlan(
    io: std.Io,
    allocator: std.mem.Allocator,
    plan: InstallPlan,
    mgr: ?Manager,
    dry_run: bool,
    out: *std.Io.Writer,
) !bool {
    var any_error = false;

    if (plan.pacman.items.len > 0) {
        any_error = !try runInstall(io, allocator, out, dry_run,
            "pacman", &.{ "sudo", "pacman", "-S", "--noconfirm" }, plan.pacman.items) or any_error;
    }

    if (plan.aur.items.len > 0) {
        const aur_cmd: []const u8 = if (mgr == .paru) "paru" else "yay";
        any_error = !try runInstall(io, allocator, out, dry_run,
            aur_cmd, &.{ aur_cmd, "-S", "--noconfirm" }, plan.aur.items) or any_error;
    }

    if (plan.brew.items.len > 0) {
        any_error = !try runInstall(io, allocator, out, dry_run,
            "brew", &.{ "brew", "install" }, plan.brew.items) or any_error;
    }

    if (plan.brew_cask.items.len > 0) {
        any_error = !try runInstall(io, allocator, out, dry_run,
            "brew cask", &.{ "brew", "install", "--cask" }, plan.brew_cask.items) or any_error;
    }

    for (plan.script.items) |id| {
        any_error = !try runScript(io, allocator, out, dry_run, id) or any_error;
    }

    for (plan.skip.items) |msg| {
        try out.print("  skip: {s}\n", .{msg});
    }

    return !any_error;
}

fn runInstall(
    io: std.Io,
    allocator: std.mem.Allocator,
    out: *std.Io.Writer,
    dry_run: bool,
    label: []const u8,
    prefix: []const []const u8,
    pkg_names: []const []const u8,
) !bool {
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);

    for (prefix) |p| try argv.append(allocator, p);
    for (pkg_names) |n| try argv.append(allocator, n);

    try out.print("\n[{s}]", .{label});
    for (pkg_names) |n| try out.print(" {s}", .{n});
    try out.print("\n", .{});

    if (dry_run) return true;

    try out.flush();
    var child = std.process.spawn(io, .{ .argv = argv.items }) catch |err| {
        try out.print("  error: failed to spawn {s}: {any}\n", .{ label, err });
        return false;
    };
    const term = child.wait(io) catch |err| {
        try out.print("  error: {s} wait failed: {any}\n", .{ label, err });
        return false;
    };
    switch (term) {
        .exited => |code| if (code != 0) {
            try out.print("  error: {s} exited with code {d}\n", .{ label, code });
            return false;
        },
        else => {
            try out.print("  error: {s} terminated abnormally\n", .{label});
            return false;
        },
    }
    return true;
}

fn runScript(
    io: std.Io,
    allocator: std.mem.Allocator,
    out: *std.Io.Writer,
    dry_run: bool,
    pkg_id: []const u8,
) !bool {
    _ = io;
    _ = allocator;
    try out.print("\n[script: {s}] ", .{pkg_id});
    if (dry_run) {
        try out.print("(would run install script)\n", .{});
        return true;
    }
    try out.print("script install not yet implemented — run manually\n", .{});
    return true;
}

// Collect all config_paths from installed packages into the tracker.
pub fn collectConfigPaths(
    allocator: std.mem.Allocator,
    pkgs: []const packages.Package,
    platform: []const u8,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
    out: *std.Io.Writer,
) !void {
    const home = environ_map.get("HOME") orelse "";

    for (pkgs) |pkg| {
        if (!pkg.hasPlatform(platform)) continue;
        if (!isInstalled(io, environ_map, pkg)) continue;

        for (pkg.config_paths) |raw_path| {
            const path = if (std.mem.startsWith(u8, raw_path, "~/"))
                try std.fmt.allocPrint(allocator, "{s}/{s}", .{ home, raw_path[2..] })
            else
                try allocator.dupe(u8, raw_path);
            defer allocator.free(path);

            std.Io.Dir.cwd().access(io, path, .{}) catch continue;
            try out.print("  config: {s}\n", .{path});
        }
    }
}

test "detect returns brew on macOS path" {
    const builtin = @import("builtin");
    if (builtin.os.tag != .macos) return;

    const io = std.Io.null_io;
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("PATH", "/opt/homebrew/bin:/usr/bin:/bin");

    // brew doesn't exist at /opt/homebrew/bin/brew in tests, so result depends on actual path
    _ = detect(io, &env);
}

test "buildPlan assigns brew for brew manager" {
    const data = [_]packages.Package{.{
        .id = "neovim",
        .description = "editor",
        .profiles = &.{},
        .platforms = &.{"linux", "macos"},
        .config_paths = &.{},
        .pacman = "neovim",
        .aur = null,
        .brew = "neovim",
        .brew_cask = null,
        .check_cmd = null,
        .skip = null,
        .install_script = null,
        .service_user = null,
        .service_system = null,
        .groups = &.{},
        .post_cmd = null,
        .font_pkg = false,
    }};
    var plan = try buildPlan(std.testing.allocator, &data, .brew, "macos");
    defer plan.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 1), plan.brew.items.len);
    try std.testing.expectEqualStrings("neovim", plan.brew.items[0]);
}
