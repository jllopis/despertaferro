const std = @import("std");
const git_backend = @import("git_backend.zig");

const manifest_path = "desperta.toml";
const denylist_path = "config/denylist.txt";
const tracked_paths_path = "config/tracked-paths.txt";
const purpose_path = "planning/purpose.md";
const plan_path = "planning/plan.md";

pub fn main(init: std.process.Init) !u8 {
    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();

    _ = args.next();
    const cmd = args.next() orelse {
        printHelp();
        return 0;
    };

    if (eql(cmd, "help") or eql(cmd, "--help") or eql(cmd, "-h")) {
        printHelp();
        return 0;
    } else if (eql(cmd, "status")) {
        try commandStatus(init.gpa, init.io, init.environ_map);
    } else if (eql(cmd, "track")) {
        return try commandAppendMany(&args, init.gpa, init.io, tracked_paths_path, "tracked path");
    } else if (eql(cmd, "ignore")) {
        return try commandAppendMany(&args, init.gpa, init.io, denylist_path, "denylist pattern");
    } else if (eql(cmd, "sync")) {
        return commandSync(&args);
    } else if (eql(cmd, "doctor")) {
        return try commandDoctor(init.gpa, init.io);
    } else {
        std.debug.print("unknown command: {s}\n\n", .{cmd});
        printHelp();
        return 1;
    }

    return 0;
}

fn commandStatus(allocator: std.mem.Allocator, io: std.Io, environ_map: *const std.process.Environ.Map) !void {
    std.debug.print("despertaferro runtime\n", .{});
    std.debug.print("manifest: {s}\n", .{present(io, manifest_path)});
    std.debug.print("denylist: {s}\n", .{present(io, denylist_path)});
    std.debug.print("tracked paths: {s}\n", .{present(io, tracked_paths_path)});
    std.debug.print("purpose: {s}\n", .{present(io, purpose_path)});
    std.debug.print("plan: {s}\n", .{present(io, plan_path)});

    if (environ_map.get("HOME")) |value| {
        std.debug.print("worktree: {s}\n", .{value});
    } else {
        std.debug.print("worktree: unknown (HOME is not set)\n", .{});
    }

    const repo_path = try resolveRepoPath(allocator, environ_map);
    defer allocator.free(repo_path);

    std.debug.print("git backend: native filesystem plumbing\n", .{});
    std.debug.print("repo path: {s}\n", .{repo_path});

    var repo = git_backend.openBare(allocator, io, repo_path) catch |err| {
        switch (err) {
            error.NotGitRepository => std.debug.print("repo: missing\n", .{}),
            error.NotBareRepository => std.debug.print("repo: present but not bare\n", .{}),
            error.InvalidHead => std.debug.print("repo: invalid HEAD\n", .{}),
            error.UnsupportedHead => std.debug.print("repo: unsupported HEAD\n", .{}),
            else => return err,
        }
        return;
    };
    defer repo.deinit(allocator);

    std.debug.print("repo: bare\n", .{});
    switch (repo.head) {
        .branch => |branch| std.debug.print("active branch: {s}\n", .{branch}),
        .detached => |object_id| std.debug.print("detached HEAD: {s}\n", .{object_id}),
    }
}

fn resolveRepoPath(allocator: std.mem.Allocator, environ_map: *const std.process.Environ.Map) ![]const u8 {
    if (environ_map.get("DESPERTA_REPO_PATH")) |value| {
        return allocator.dupe(u8, value);
    }

    if (environ_map.get("XDG_STATE_HOME")) |value| {
        return std.fmt.allocPrint(allocator, "{s}/despertaferro/repo.git", .{value});
    }

    if (environ_map.get("HOME")) |value| {
        return std.fmt.allocPrint(allocator, "{s}/.local/state/despertaferro/repo.git", .{value});
    }

    return error.MissingHome;
}

fn commandAppendMany(
    args: *std.process.Args.Iterator,
    allocator: std.mem.Allocator,
    io: std.Io,
    file_path: []const u8,
    label: []const u8,
) !u8 {
    var added_any = false;
    while (args.next()) |value| {
        added_any = true;
        if (try containsLine(allocator, io, file_path, value)) {
            std.debug.print("{s} already present: {s}\n", .{ label, value });
        } else {
            try appendLine(io, file_path, value);
            std.debug.print("added {s}: {s}\n", .{ label, value });
        }
    }

    if (!added_any) {
        std.debug.print("missing {s}\n", .{label});
        return 1;
    }

    return 0;
}

fn commandSync(args: *std.process.Args.Iterator) u8 {
    var apply = false;
    while (args.next()) |arg| {
        if (eql(arg, "--apply")) {
            apply = true;
        }
    }

    std.debug.print("sync plan\n", .{});
    std.debug.print("- read manifest from {s}\n", .{manifest_path});
    std.debug.print("- open bare repo from configured runtime state path\n", .{});
    std.debug.print("- compare tracked paths against worktree\n", .{});
    std.debug.print("- refuse denylisted paths from {s}\n", .{denylist_path});
    std.debug.print("- create snapshot before apply\n", .{});

    if (apply) {
        std.debug.print("apply requested, but native Git backend is not implemented yet\n", .{});
        return 2;
    }

    std.debug.print("dry-run only: no files changed and no git binary invoked\n", .{});
    return 0;
}

fn commandDoctor(allocator: std.mem.Allocator, io: std.Io) !u8 {
    var ok = true;
    ok = checkExists(io, manifest_path, "manifest") and ok;
    ok = checkExists(io, denylist_path, "denylist") and ok;
    ok = checkExists(io, tracked_paths_path, "tracked paths") and ok;
    ok = checkExists(io, purpose_path, "purpose document") and ok;
    ok = checkExists(io, plan_path, "implementation plan") and ok;

    const required_patterns = [_][]const u8{
        ".config/zsh/.zsh_history",
        ".config/zsh/.zcompdump",
        ".config/zsh/.zcompcache/",
        "*.log",
        ".env",
        "*.pem",
        "*token*",
        "*secret*",
        "*password*",
    };

    for (required_patterns) |pattern| {
        if (try containsLine(allocator, io, denylist_path, pattern)) {
            std.debug.print("ok: denylist includes {s}\n", .{pattern});
        } else {
            ok = false;
            std.debug.print("warn: denylist missing {s}\n", .{pattern});
        }
    }

    if (ok) {
        std.debug.print("doctor: ok\n", .{});
        return 0;
    } else {
        std.debug.print("doctor: issues found\n", .{});
        return 1;
    }
}

fn checkExists(io: std.Io, path: []const u8, label: []const u8) bool {
    if (exists(io, path)) {
        std.debug.print("ok: {s} exists ({s})\n", .{ label, path });
        return true;
    }

    std.debug.print("missing: {s} ({s})\n", .{ label, path });
    return false;
}

fn containsLine(allocator: std.mem.Allocator, io: std.Io, file_path: []const u8, value: []const u8) !bool {
    var file = std.Io.Dir.cwd().openFile(io, file_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer file.close(io);

    const stat = try file.stat(io);
    if (stat.size > 1024 * 1024) {
        return error.FileTooBig;
    }

    const len: usize = @intCast(stat.size);
    const data = try allocator.alloc(u8, len);
    defer allocator.free(data);
    const bytes_read = try file.readPositionalAll(io, data, 0);

    var lines = std.mem.splitScalar(u8, data[0..bytes_read], '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') {
            continue;
        }
        if (eql(trimmed, value)) {
            return true;
        }
    }

    return false;
}

fn appendLine(io: std.Io, file_path: []const u8, value: []const u8) !void {
    if (std.fs.path.dirname(file_path)) |dir| {
        try std.Io.Dir.cwd().createDirPath(io, dir);
    }

    var file = try std.Io.Dir.cwd().createFile(io, file_path, .{
        .read = true,
        .truncate = false,
    });
    defer file.close(io);

    const stat = try file.stat(io);
    try file.writePositionalAll(io, value, stat.size);
    try file.writePositionalAll(io, "\n", stat.size + value.len);
}

fn present(io: std.Io, path: []const u8) []const u8 {
    return if (exists(io, path)) "present" else "missing";
}

fn exists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn printHelp() void {
    std.debug.print(
        \\desperta - personal configuration runtime
        \\
        \\usage:
        \\  desperta status
        \\  desperta track <path>...
        \\  desperta ignore <pattern>...
        \\  desperta sync [--apply]
        \\  desperta doctor
        \\
        \\sync is dry-run until the native Git backend is implemented.
        \\
    , .{});
}
