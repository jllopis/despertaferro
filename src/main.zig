const std = @import("std");
const git_backend = @import("git_backend.zig");
const config = @import("config.zig");
const manifest = @import("manifest.zig");
const detect = @import("detect.zig");
const packages = @import("packages.zig");
const pkgmgr = @import("pkgmgr.zig");
const services = @import("services.zig");
const dotfiles = @import("dotfiles.zig");

const denylist_path = "config/denylist.txt";
const tracked_paths_path = "config/tracked-paths.txt";

const Flags = struct {
    host: ?[]const u8 = null,
    from: ?[]const u8 = null,
    to: ?[]const u8 = null,
    adopt: ?[]const u8 = null,
    profile: ?[]const u8 = null,
    apply: bool = false,
    json: bool = false,
    system: bool = false,
    force: bool = false,

    fn parse(args: *std.process.Args.Iterator) Flags {
        var f: Flags = .{};
        while (args.next()) |arg| {
            if (eql(arg, "--apply")) {
                f.apply = true;
            } else if (eql(arg, "--json")) {
                f.json = true;
            } else if (eql(arg, "--system")) {
                f.system = true;
            } else if (eql(arg, "--host")) {
                f.host = args.next();
            } else if (eql(arg, "--from")) {
                f.from = args.next();
            } else if (eql(arg, "--to")) {
                f.to = args.next();
            } else if (eql(arg, "--adopt")) {
                f.adopt = args.next();
            } else if (eql(arg, "--profile")) {
                f.profile = args.next();
            } else if (eql(arg, "--force")) {
                f.force = true;
            }
        }
        return f;
    }
};

pub fn main(init: std.process.Init) !u8 {
    var out_buf: [4096]u8 = undefined;
    // Item 2: write user-facing output to stdout, not stderr.
    var file_writer = std.Io.File.stdout().writer(init.io, &out_buf);
    defer file_writer.interface.flush() catch {};
    const out = &file_writer.interface;

    var args = try std.process.Args.Iterator.initAllocator(init.minimal.args, init.gpa);
    defer args.deinit();
    _ = args.next();

    const cmd = args.next() orelse {
        try printHelp(out);
        return 0;
    };

    if (eql(cmd, "help") or eql(cmd, "--help") or eql(cmd, "-h")) {
        try printHelp(out);
    } else if (eql(cmd, "status")) {
        try commandStatus(out, init.gpa, init.io, init.environ_map);
    } else if (eql(cmd, "track")) {
        return try commandTrack(&args, out, init.gpa, init.io, init.environ_map);
    } else if (eql(cmd, "ignore")) {
        return try commandIgnore(&args, out, init.gpa, init.io);
    } else if (eql(cmd, "sync")) {
        return try commandSync(&args, out, init.gpa, init.io, init.environ_map);
    } else if (eql(cmd, "doctor")) {
        return try commandDoctor(out, init.gpa, init.io, init.environ_map);
    } else if (eql(cmd, "init")) {
        return try commandInit(&args, out, init.gpa, init.io, init.environ_map);
    } else if (eql(cmd, "snapshot")) {
        return try commandSnapshot(out, init.gpa, init.io, init.environ_map);
    } else if (eql(cmd, "migrate")) {
        return try commandMigrate(&args, out, init.gpa, init.io, init.environ_map);
    } else if (eql(cmd, "list")) {
        return try commandList(&args, out, init.gpa, init.io, init.environ_map);
    } else if (eql(cmd, "install")) {
        return try commandInstall(&args, out, init.gpa, init.io, init.environ_map);
    } else if (eql(cmd, "bootstrap")) {
        return try commandBootstrap(&args, out, init.gpa, init.io, init.environ_map);
    } else if (eql(cmd, "service")) {
        return try commandService(&args, out, init.gpa, init.io, init.environ_map);
    } else {
        try out.print("unknown command: {s}\n\n", .{cmd});
        try printHelp(out);
        return 1;
    }

    return 0;
}

fn commandStatus(
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
) !void {
    var cfg = try config.load(allocator, io, environ_map);
    defer cfg.deinit(allocator);

    var m = try manifest.load(allocator, io, environ_map);
    defer m.deinit(allocator);

    const worktree_path = try resolveWorktreePath(allocator, environ_map, &cfg);
    defer allocator.free(worktree_path);

    const repo_path = try resolveRepoPath(allocator, environ_map, &cfg);
    defer allocator.free(repo_path);

    try out.print("despertaferro runtime\n", .{});
    if (m.name) |n| try out.print("manifest: {s} (schema v{d})\n", .{ n, m.schema_version });
    try out.print("worktree: {s}\n", .{worktree_path});
    try out.print("repo path: {s}\n", .{repo_path});

    var repo = git_backend.openBare(allocator, io, repo_path) catch |err| {
        switch (err) {
            error.NotGitRepository => try out.print("repo: missing (run desperta init)\n", .{}),
            error.NotBareRepository => try out.print("repo: present but not bare\n", .{}),
            error.InvalidHead => try out.print("repo: invalid HEAD\n", .{}),
            error.UnsupportedHead => try out.print("repo: unsupported HEAD\n", .{}),
            else => return err,
        }
        return;
    };
    defer repo.deinit(allocator);

    try out.print("repo: bare\n", .{});
    switch (repo.head) {
        .branch => |branch| {
            try out.print("active branch: {s}\n", .{branch});
            // Show profiles for the active host from manifest.
            // Each host's branch is always `hosts/<name>`.
            if (m.hosts) |hs| {
                for (hs) |h| {
                    const expected = try std.fmt.allocPrint(allocator, "hosts/{s}", .{h.name});
                    defer allocator.free(expected);
                    if (std.mem.eql(u8, expected, branch)) {
                        try out.print("host: {s} ({s})  profiles:", .{ h.name, h.platform });
                        for (h.profiles) |p| try out.print(" {s}", .{p});
                        try out.print("\n", .{});
                        break;
                    }
                }
            }
        },
        .detached => |oid| try out.print("detached HEAD: {s}\n", .{oid}),
    }

    const ws = git_backend.statusWorktree(allocator, io, repo, worktree_path) catch |err| {
        switch (err) {
            error.IndexMissing => try out.print("worktree status: no commits yet\n", .{}),
            error.InvalidIndex => try out.print("worktree status: invalid index\n", .{}),
            error.UnsupportedIndexVersion => try out.print("worktree status: unsupported index version\n", .{}),
            else => return err,
        }
        return;
    };

    try out.print("tracked: {d}  clean: {d}  modified: {d}  deleted: {d}\n", .{
        ws.tracked, ws.clean, ws.modified, ws.deleted,
    });
}

// Item 1: track validates paths against the denylist before adding.
fn commandTrack(
    args: *std.process.Args.Iterator,
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
) !u8 {
    _ = environ_map;

    // Item 8: parse flags and positional paths in one pass.
    var json = false;
    var paths = std.ArrayList([]const u8).empty;
    defer paths.deinit(allocator);

    while (args.next()) |arg| {
        if (eql(arg, "--json")) {
            json = true;
        } else {
            try paths.append(allocator, arg);
        }
    }

    if (paths.items.len == 0) {
        if (json) {
            try out.print("{{\"error\":\"missing path\"}}\n", .{});
        } else {
            try out.print("missing path\n", .{});
        }
        return 1;
    }

    var added = std.ArrayList([]const u8).empty;
    defer added.deinit(allocator);
    var already = std.ArrayList([]const u8).empty;
    defer already.deinit(allocator);
    var denied = std.ArrayList([]const u8).empty;
    defer denied.deinit(allocator);

    for (paths.items) |p| {
        // Item 1: refuse paths that match denylist patterns.
        if (try isDenylisted(allocator, io, p)) {
            try denied.append(allocator, p);
            continue;
        }
        if (try containsLine(allocator, io, tracked_paths_path, p)) {
            try already.append(allocator, p);
        } else {
            try appendLine(io, tracked_paths_path, p);
            try added.append(allocator, p);
        }
    }

    // Item 9: structured JSON output when --json is requested.
    if (json) {
        try out.print("{{\"added\":[", .{});
        for (added.items, 0..) |p, i| {
            if (i > 0) try out.print(",", .{});
            try out.print("\"{s}\"", .{p});
        }
        try out.print("],\"already_present\":[", .{});
        for (already.items, 0..) |p, i| {
            if (i > 0) try out.print(",", .{});
            try out.print("\"{s}\"", .{p});
        }
        try out.print("],\"denied\":[", .{});
        for (denied.items, 0..) |p, i| {
            if (i > 0) try out.print(",", .{});
            try out.print("\"{s}\"", .{p});
        }
        try out.print("]}}\n", .{});
    } else {
        for (added.items) |p| try out.print("tracked: {s}\n", .{p});
        for (already.items) |p| try out.print("already tracked: {s}\n", .{p});
        for (denied.items) |p| try out.print("denied (denylist): {s}\n", .{p});
    }

    return if (denied.items.len > 0 and added.items.len == 0 and already.items.len == 0) 1 else 0;
}

fn commandIgnore(
    args: *std.process.Args.Iterator,
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    io: std.Io,
) !u8 {
    var added_any = false;
    while (args.next()) |value| {
        if (eql(value, "--json")) continue;
        added_any = true;
        if (try containsLine(allocator, io, denylist_path, value)) {
            try out.print("already in denylist: {s}\n", .{value});
        } else {
            try appendLine(io, denylist_path, value);
            try out.print("added to denylist: {s}\n", .{value});
        }
    }

    if (!added_any) {
        try out.print("missing denylist pattern\n", .{});
        return 1;
    }
    return 0;
}

fn commandSync(
    args: *std.process.Args.Iterator,
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
) !u8 {
    _ = io;
    // Item 8: use structured flag parsing.
    const flags = Flags.parse(args);

    // Item 9: JSON output for sync plan.
    if (flags.json) {
        try out.print("{{\"dry_run\":{},\"apply\":{}}}\n", .{ !flags.apply, flags.apply });
        return 0;
    }

    const repo_path = try resolveRepoPath(allocator, environ_map, &config.Config{});
    defer allocator.free(repo_path);

    try out.print("sync plan\n", .{});
    try out.print("  - read manifest\n", .{});
    try out.print("  - open repo at {s}\n", .{repo_path});
    try out.print("  - compare tracked paths against worktree\n", .{});
    try out.print("  - refuse denylisted paths\n", .{});
    try out.print("  - create snapshot before apply\n", .{});

    if (flags.apply) {
        try out.print("--apply requested: use desperta snapshot first, then sync --apply\n", .{});
        return 2;
    }

    try out.print("dry-run: no files changed\n", .{});
    return 0;
}

fn commandDoctor(
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
) !u8 {
    var cfg = try config.load(allocator, io, environ_map);
    defer cfg.deinit(allocator);

    var m = try manifest.load(allocator, io, environ_map);
    defer m.deinit(allocator);

    const required_files = [_]struct { path: []const u8, label: []const u8 }{
        .{ .path = "desperta.toml", .label = "manifest" },
        .{ .path = denylist_path, .label = "denylist" },
        .{ .path = tracked_paths_path, .label = "tracked paths" },
    };

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

    var ok = true;

    for (required_files) |f| {
        if (fileExists(io, f.path)) {
            try out.print("ok: {s} ({s})\n", .{ f.label, f.path });
        } else {
            try out.print("missing: {s} ({s})\n", .{ f.label, f.path });
            ok = false;
        }
    }

    for (required_patterns) |pattern| {
        if (try containsLine(allocator, io, denylist_path, pattern)) {
            try out.print("ok: denylist includes {s}\n", .{pattern});
        } else {
            try out.print("warn: denylist missing {s}\n", .{pattern});
            ok = false;
        }
    }

    // Item 4: check runtime config.
    const cfg_path = config.configPath(allocator, environ_map) catch null;
    if (cfg_path) |p| {
        defer allocator.free(p);
        if (fileExists(io, p)) {
            try out.print("ok: runtime config ({s})\n", .{p});
            if (cfg.repo_path) |rp| try out.print("ok: runtime repo_path = {s}\n", .{rp});
            if (cfg.worktree) |wt| try out.print("ok: runtime work_tree = {s}\n", .{wt});
        } else {
            try out.print("warn: runtime config missing -- run desperta init\n", .{});
        }
    }

    // Validate manifest.
    if (m.schema_version == 0) {
        try out.print("warn: desperta.toml missing or unreadable\n", .{});
        ok = false;
    } else {
        try out.print("ok: manifest schema v{d}\n", .{m.schema_version});
        if (m.runtime.repo_path) |rp| try out.print("ok: manifest repo_path = {s}\n", .{rp});
        if (m.policy.require_snapshot_before_apply) {
            try out.print("ok: policy requires snapshot before apply\n", .{});
        }
        if (m.hosts) |hs| {
            try out.print("ok: {d} host(s) defined\n", .{hs.len});
        } else {
            try out.print("warn: no hosts defined in manifest\n", .{});
            ok = false;
        }
    }

    if (ok) {
        try out.print("doctor: ok\n", .{});
        return 0;
    } else {
        try out.print("doctor: issues found\n", .{});
        return 1;
    }
}

// Item 3: initialize a new despertaferro setup for a host.
fn commandInit(
    args: *std.process.Args.Iterator,
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
) !u8 {
    // Item 8: structured flag parsing.
    const flags = Flags.parse(args);

    const hostname = blk: {
        if (flags.host) |h| break :blk try allocator.dupe(u8, h);
        var buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
        const name = try std.posix.gethostname(&buf);
        break :blk try allocator.dupe(u8, name);
    };
    defer allocator.free(hostname);

    var empty_cfg = config.Config{};
    const repo_path = try resolveRepoPath(allocator, environ_map, &empty_cfg);
    defer allocator.free(repo_path);
    const worktree_path = try resolveWorktreePath(allocator, environ_map, &empty_cfg);
    defer allocator.free(worktree_path);

    const sysinfo = try detect.detect(allocator, io, environ_map);
    defer sysinfo.deinit(allocator);

    try out.print("initializing despertaferro for host: {s}\n", .{hostname});
    try out.print("detected: os={s} shell={s}\n", .{ sysinfo.os_id, sysinfo.shell });

    // Create bare repository structure.
    if (fileExists(io, repo_path)) {
        try out.print("repo already exists at {s}\n", .{repo_path});
    } else {
        try initBareRepo(allocator, io, repo_path, hostname);
        try out.print("created bare repo: {s}\n", .{repo_path});
    }

    // Write runtime config.
    const cfg_path = try config.configPath(allocator, environ_map);
    defer allocator.free(cfg_path);

    if (std.fs.path.dirname(cfg_path)) |dir| {
        try std.Io.Dir.cwd().createDirPath(io, dir);
    }
    try writeRuntimeConfig(io, cfg_path, repo_path, worktree_path);
    try out.print("wrote runtime config: {s}\n", .{cfg_path});

    try out.print("init complete. run: desperta doctor\n", .{});
    return 0;
}

// Item 6: create a point-in-time snapshot of all tracked files.
fn commandSnapshot(
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
) !u8 {
    var cfg = try config.load(allocator, io, environ_map);
    defer cfg.deinit(allocator);

    const repo_path = try resolveRepoPath(allocator, environ_map, &cfg);
    defer allocator.free(repo_path);
    const worktree_path = try resolveWorktreePath(allocator, environ_map, &cfg);
    defer allocator.free(worktree_path);

    var repo = git_backend.openBare(allocator, io, repo_path) catch |err| {
        switch (err) {
            error.NotGitRepository => {
                try out.print("repo not initialized. run desperta init\n", .{});
                return 1;
            },
            else => return err,
        }
    };
    defer repo.deinit(allocator);

    const snap_base = try resolveSnapshotBase(allocator, environ_map);
    defer allocator.free(snap_base);

    const ts = std.Io.Timestamp.now(io, .real).toSeconds();
    const snap_dir = try std.fmt.allocPrint(allocator, "{s}/{d}", .{ snap_base, ts });
    defer allocator.free(snap_dir);

    try std.Io.Dir.cwd().createDirPath(io, snap_dir);

    const index_path = try std.fmt.allocPrint(allocator, "{s}/index", .{repo_path});
    defer allocator.free(index_path);

    const index_data = std.Io.Dir.cwd().readFileAlloc(io, index_path, allocator, .limited(64 * 1024 * 1024)) catch |err| switch (err) {
        error.FileNotFound => {
            try out.print("no tracked files yet. use desperta track <path>\n", .{});
            return 0;
        },
        else => return err,
    };
    defer allocator.free(index_data);

    var entries = std.ArrayList(git_backend.IndexEntry).empty;
    defer {
        for (entries.items) |e| e.deinit(allocator);
        entries.deinit(allocator);
    }

    git_backend.parseIndexEntries(allocator, index_data, &entries) catch |err| {
        try out.print("failed to read index: {any}\n", .{err});
        return 1;
    };

    var copied: u32 = 0;
    var skipped: u32 = 0;

    for (entries.items) |e| {
        const src = try std.fs.path.join(allocator, &.{ worktree_path, e.path });
        defer allocator.free(src);

        const dst = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ snap_dir, e.path });
        defer allocator.free(dst);

        if (std.fs.path.dirname(dst)) |dir| {
            std.Io.Dir.cwd().createDirPath(io, dir) catch {};
        }

        const data = std.Io.Dir.cwd().readFileAlloc(io, src, allocator, .unlimited) catch {
            skipped += 1;
            continue;
        };
        defer allocator.free(data);

        var f = std.Io.Dir.cwd().createFile(io, dst, .{}) catch {
            skipped += 1;
            continue;
        };
        defer f.close(io);
        f.writePositionalAll(io, data, 0) catch {
            skipped += 1;
            continue;
        };
        copied += 1;
    }

    // Write snapshot manifest.
    const manifest_path = try std.fmt.allocPrint(allocator, "{s}/MANIFEST", .{snap_dir});
    defer allocator.free(manifest_path);

    var mf = try std.Io.Dir.cwd().createFile(io, manifest_path, .{});
    defer mf.close(io);

    var mf_buf: [128]u8 = undefined;
    var mf_writer = mf.writer(io, &mf_buf);
    try mf_writer.interface.print("timestamp: {d}\n", .{ts});
    try mf_writer.interface.print("worktree: {s}\n", .{worktree_path});
    try mf_writer.interface.print("files: {d}\n", .{copied});
    for (entries.items) |e| {
        try mf_writer.interface.print("  {s}\n", .{e.path});
    }
    try mf_writer.interface.flush();

    try out.print("snapshot: {s}\n", .{snap_dir});
    try out.print("files: {d} copied, {d} skipped\n", .{ copied, skipped });
    return 0;
}

fn commandList(
    args: *std.process.Args.Iterator,
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
) !u8 {
    const flags = Flags.parse(args);

    var catalog = try packages.load(allocator, io);
    defer catalog.deinit(allocator);

    if (catalog.packages.len == 0) {
        try out.print("no packages defined. create config/packages.toml\n", .{});
        return 1;
    }

    const sysinfo = try detect.detect(allocator, io, environ_map);
    defer sysinfo.deinit(allocator);

    const profile_filter = flags.host; // reuse --host flag as profile filter for list
    var installed: u32 = 0;
    var pending: u32 = 0;

    try out.print("{s:<24} {s:<12} {s:<12} {s}\n", .{ "package", "status", "profile", "description" });
    try out.print("{s}\n", .{"─" ** 72});

    for (catalog.packages) |pkg| {
        if (!pkg.hasPlatform(sysinfo.os_id) and
            !(std.mem.eql(u8, sysinfo.os_id, "macos") and pkg.hasPlatform("macos")) and
            !(std.mem.eql(u8, sysinfo.os_id, "linux") and pkg.hasPlatform("linux")))
        {
            if (pkg.hasPlatform("linux") or pkg.hasPlatform("macos")) {} else continue;
        }
        if (profile_filter) |pf| {
            if (!pkg.hasProfile(pf)) continue;
        }

        const status = if (pkgmgr.isInstalled(io, environ_map, pkg)) "installed" else "pending";
        if (std.mem.eql(u8, status, "installed")) {
            installed += 1;
        } else {
            pending += 1;
        }

        var profile_buf = std.ArrayList(u8).empty;
        defer profile_buf.deinit(allocator);
        for (pkg.profiles, 0..) |p, i| {
            if (i > 0) try profile_buf.append(allocator, ',');
            try profile_buf.appendSlice(allocator, p);
        }
        try out.print("{s:<24} {s:<12} {s:<12} {s}\n", .{ pkg.id, status, profile_buf.items, pkg.description });
    }

    try out.print("{s}\n", .{"─" ** 72});
    try out.print("installed: {d}  pending: {d}\n", .{ installed, pending });
    return 0;
}

fn commandInstall(
    args: *std.process.Args.Iterator,
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
) !u8 {
    const flags = Flags.parse(args);
    const dry_run = !flags.apply;

    if (dry_run) {
        try out.print("dry-run: pass --apply to actually install\n\n", .{});
    }

    var catalog = try packages.load(allocator, io);
    defer catalog.deinit(allocator);

    if (catalog.packages.len == 0) {
        try out.print("no packages defined. create config/packages.toml\n", .{});
        return 1;
    }

    const sysinfo = try detect.detect(allocator, io, environ_map);
    defer sysinfo.deinit(allocator);

    const mgr = pkgmgr.detect(io, environ_map);
    if (mgr) |m| {
        try out.print("package manager: {s}\n", .{@tagName(m)});
    } else {
        try out.print("warn: no supported package manager detected\n", .{});
    }
    try out.print("platform: {s}\n\n", .{sysinfo.os_id});

    const profile = flags.host orelse "base"; // --host reused as --profile for install

    var to_install = std.ArrayList(packages.Package).empty;
    defer to_install.deinit(allocator);

    for (catalog.packages) |pkg| {
        if (!pkg.hasProfile(profile)) continue;
        if (!pkg.hasPlatform(sysinfo.os_id) and
            !(std.mem.eql(u8, sysinfo.os_id, "macos") and pkg.hasPlatform("macos")) and
            !(std.mem.eql(u8, sysinfo.os_id, "linux") and pkg.hasPlatform("linux"))) continue;
        if (pkgmgr.isInstalled(io, environ_map, pkg)) continue;
        try to_install.append(allocator, pkg);
    }

    if (to_install.items.len == 0) {
        try out.print("all packages in profile '{s}' are already installed\n", .{profile});
        return 0;
    }

    try out.print("pending ({s} profile): {d} packages\n", .{ profile, to_install.items.len });

    const canonical_platform_install: []const u8 = switch (sysinfo.os) {
        .linux => "linux",
        .macos => "macos",
        else => sysinfo.os_id,
    };
    var plan = try pkgmgr.buildPlan(allocator, to_install.items, mgr, canonical_platform_install);
    defer plan.deinit(allocator);

    const ok = try pkgmgr.executePlan(io, allocator, plan, mgr, dry_run, out);
    return if (ok) 0 else 1;
}

fn commandBootstrap(
    args: *std.process.Args.Iterator,
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
) !u8 {
    const flags = Flags.parse(args);
    const dry_run = !flags.apply;

    if (dry_run) {
        try out.print("bootstrap dry-run: pass --apply to execute\n\n", .{});
    }

    const sysinfo = try detect.detect(allocator, io, environ_map);
    defer sysinfo.deinit(allocator);

    // Phase 0: Pre-flight checks
    try out.print("phase 0: pre-flight\n", .{});

    const uid = std.c.getuid();
    if (uid == 0) {
        try out.print("  error: do not run bootstrap as root\n", .{});
        return 1;
    }
    if (!pkgmgr.isInPath(io, environ_map, "sudo")) {
        try out.print("  error: 'sudo' not found in PATH\n", .{});
        return 1;
    }
    std.Io.Dir.cwd().access(io, "config/packages.toml", .{}) catch {
        try out.print("  error: config/packages.toml not found — run from repo root\n", .{});
        return 1;
    };

    const is_linux = sysinfo.os == .linux;
    const is_arch_like = std.mem.eql(u8, sysinfo.os_id, "arch") or
        std.mem.eql(u8, sysinfo.os_id, "cachyos") or
        std.mem.eql(u8, sysinfo.os_id, "manjaro");

    if (is_linux and !is_arch_like) {
        try out.print("  warn: os '{s}' is not Arch-based — some packages may not install\n", .{sysinfo.os_id});
    }
    if (is_linux and !pkgmgr.isInPath(io, environ_map, "yay") and !pkgmgr.isInPath(io, environ_map, "paru")) {
        try out.print("  error: AUR helper (yay/paru) not found\n", .{});
        try out.print("    install with: git clone https://aur.archlinux.org/yay-bin.git /tmp/yay-bin && (cd /tmp/yay-bin && makepkg -si --noconfirm)\n", .{});
        return 1;
    }

    const hostname = flags.host orelse flags.adopt orelse sysinfo.hostname;
    try out.print("  ok: uid={d}  host={s}  os={s}  shell={s}\n", .{ uid, hostname, sysinfo.os_id, sysinfo.shell });

    // Phase 1: System update
    try out.print("\nphase 1: system update\n", .{});
    if (is_linux and is_arch_like) {
        if (dry_run) {
            try out.print("  would run: sudo pacman -Syu --noconfirm\n", .{});
        } else {
            var argv = std.ArrayList([]const u8).empty;
            defer argv.deinit(allocator);
            try argv.append(allocator, "sudo");
            try argv.append(allocator, "pacman");
            try argv.append(allocator, "-Syu");
            try argv.append(allocator, "--noconfirm");
            var child = std.process.spawn(io, .{ .argv = argv.items }) catch |err| {
                try out.print("  error: spawn pacman: {any}\n", .{err});
                return 1;
            };
            const term = child.wait(io) catch |err| {
                try out.print("  error: pacman wait: {any}\n", .{err});
                return 1;
            };
            switch (term) {
                .exited => |code| if (code != 0) {
                    try out.print("  error: pacman -Syu exited {d}\n", .{code});
                    return 1;
                },
                else => {
                    try out.print("  error: pacman terminated abnormally\n", .{});
                    return 1;
                },
            }
            try out.print("  system updated\n", .{});
        }
    } else {
        try out.print("  skipped (not Arch-based)\n", .{});
    }

    // Phase 2: Init repo
    try out.print("\nphase 2: init repo\n", .{});
    var empty_cfg = config.Config{};
    const repo_path = try resolveRepoPath(allocator, environ_map, &empty_cfg);
    defer allocator.free(repo_path);
    if (!fileExists(io, repo_path)) {
        if (dry_run) {
            try out.print("  would create bare repo: {s}\n", .{repo_path});
        } else {
            try initBareRepo(allocator, io, repo_path, hostname);
            try out.print("  created bare repo: {s}\n", .{repo_path});
            const cfg_path = try config.configPath(allocator, environ_map);
            defer allocator.free(cfg_path);
            if (std.fs.path.dirname(cfg_path)) |dir| {
                try std.Io.Dir.cwd().createDirPath(io, dir);
            }
            const worktree_path = try resolveWorktreePath(allocator, environ_map, &empty_cfg);
            defer allocator.free(worktree_path);
            try writeRuntimeConfig(io, cfg_path, repo_path, worktree_path);
            try out.print("  wrote runtime config\n", .{});
        }
    } else {
        try out.print("  repo already exists: {s}\n", .{repo_path});
    }

    // Phase 3: Resolve profiles
    try out.print("\nphase 3: resolve profiles\n", .{});
    var m = try manifest.load(allocator, io, environ_map);
    defer m.deinit(allocator);

    var host_profiles = std.ArrayList([]const u8).empty;
    defer host_profiles.deinit(allocator);

    const adopt_host = flags.adopt;
    const from_host = flags.from;
    const source_host = adopt_host orelse from_host orelse hostname;

    if (flags.profile) |p| {
        try host_profiles.append(allocator, p);
        try out.print("  --profile override: using profile '{s}'\n", .{p});
    } else if (m.findHost(source_host)) |hc| {
        for (hc.profiles) |p| try host_profiles.append(allocator, p);
        if (adopt_host != null) {
            try out.print("  adopting host '{s}' profiles\n", .{source_host});
        } else if (from_host != null) {
            try out.print("  copying profiles from host '{s}'\n", .{source_host});
        } else {
            try out.print("  host '{s}' found in manifest\n", .{hostname});
        }
    } else {
        try host_profiles.append(allocator, "base");
        try out.print("  host '{s}' not in manifest, using default: base\n", .{source_host});
    }
    for (host_profiles.items) |p| try out.print("  profile: {s}\n", .{p});

    var catalog = try packages.load(allocator, io);
    defer catalog.deinit(allocator);

    // Phase 4: Install packages
    try out.print("\nphase 4: install packages\n", .{});
    const mgr = pkgmgr.detect(io, environ_map);
    if (mgr) |mv| {
        try out.print("  package manager: {s}\n", .{@tagName(mv)});
    } else {
        try out.print("  warn: no package manager detected\n", .{});
    }

    for (host_profiles.items) |profile| {
        var to_install = std.ArrayList(packages.Package).empty;
        defer to_install.deinit(allocator);

        for (catalog.packages) |pkg| {
            if (!pkg.hasProfile(profile)) continue;
            if (!platformMatches(sysinfo.os_id, pkg)) continue;
            if (pkgmgr.isInstalled(io, environ_map, pkg)) continue;
            try to_install.append(allocator, pkg);
        }

        if (to_install.items.len == 0) {
            try out.print("  profile '{s}': all installed\n", .{profile});
            continue;
        }
        try out.print("  profile '{s}': {d} pending\n", .{ profile, to_install.items.len });

        const canonical_platform: []const u8 = switch (sysinfo.os) {
            .linux => "linux",
            .macos => "macos",
            else => sysinfo.os_id,
        };
        var plan = try pkgmgr.buildPlan(allocator, to_install.items, mgr, canonical_platform);
        defer plan.deinit(allocator);
        _ = try pkgmgr.executePlan(io, allocator, plan, mgr, dry_run, out);
    }

    // Phase 5: Deploy dotfiles
    try out.print("\nphase 5: deploy dotfiles\n", .{});
    const repo_dir = environ_map.get("DESPERTA_REPO") orelse ".";
    const template_dir = try dotfiles.resolveTemplateDir(allocator, io, repo_dir, from_host orelse adopt_host);
    defer allocator.free(template_dir);

    const home = environ_map.get("HOME") orelse "";
    const xdg_config_home = environ_map.get("XDG_CONFIG_HOME") orelse
        try std.fmt.allocPrint(allocator, "{s}/.config", .{home});
    defer if (environ_map.get("XDG_CONFIG_HOME") == null) allocator.free(xdg_config_home);

    try out.print("  templates: {s}\n", .{template_dir});
    var deploy_result = try dotfiles.deploy(io, allocator, home, xdg_config_home, template_dir, dry_run, flags.force, out);
    defer deploy_result.deinit(allocator);
    try out.print("  deployed: {d} files, skipped: {d}\n", .{ deploy_result.deployed, deploy_result.skipped });

    // Phase 6: Post-install per-package (services, groups, post_cmd, font cache)
    try out.print("\nphase 6: post-install\n", .{});
    var any_font_pkg = false;
    var groups_added = false;
    var shell_changed = false;
    const username = environ_map.get("USER") orelse environ_map.get("LOGNAME") orelse
        std.fs.path.basename(environ_map.get("HOME") orelse "");

    for (catalog.packages) |pkg| {
        var in_profile = false;
        for (host_profiles.items) |profile| {
            if (pkg.hasProfile(profile)) { in_profile = true; break; }
        }
        if (!in_profile) continue;
        if (!platformMatches(sysinfo.os_id, pkg)) continue;
        if (!dry_run and !pkgmgr.isInstalled(io, environ_map, pkg)) continue;

        if (pkg.service_system) |svc| {
            _ = try services.enableSystemService(io, allocator, out, svc, dry_run);
        }
        if (pkg.service_user) |svc| {
            _ = try services.enableUserService(io, allocator, out, svc, environ_map, dry_run);
        }
        for (pkg.groups) |grp| {
            _ = try services.addUserToGroup(io, allocator, out, grp, username, dry_run);
            groups_added = true;
        }
        if (pkg.post_cmd) |cmd| {
            const is_chsh = std.mem.indexOf(u8, cmd, "chsh") != null;
            if (is_chsh) {
                if (parseChshTarget(cmd)) |target| {
                    const current = (getCurrentLoginShell(allocator, io, username) catch null);
                    defer if (current) |c| allocator.free(c);
                    if (current != null and std.mem.eql(u8, current.?, target)) {
                        try out.print("\n[post-cmd] chsh -s {s} — skip (already current shell)\n", .{target});
                        continue;
                    }
                }
            }
            const ok = try services.runPostCmd(io, allocator, out, cmd, environ_map, dry_run);
            if (is_chsh and ok) shell_changed = true;
        }
        if (pkg.font_pkg) any_font_pkg = true;
    }

    if (any_font_pkg) {
        _ = try services.rebuildFontCache(io, allocator, out, dry_run);
    }

    // Phase 7: Track config paths
    try out.print("\nphase 7: track configs\n", .{});

    // Open bare repo for staging
    var cfg_p7 = try config.load(allocator, io, environ_map);
    defer cfg_p7.deinit(allocator);
    const repo_path_p7 = try resolveRepoPath(allocator, environ_map, &cfg_p7);
    defer allocator.free(repo_path_p7);
    const worktree_path_p7 = try resolveWorktreePath(allocator, environ_map, &cfg_p7);
    defer allocator.free(worktree_path_p7);

    var repo_p7_opt: ?git_backend.BareRepository = if (dry_run) null else (git_backend.openBare(allocator, io, repo_path_p7) catch |err| blk: {
        try out.print("  warn: cannot open repo for staging: {any}\n", .{err});
        break :blk null;
    });
    defer if (repo_p7_opt) |*r| r.deinit(allocator);

    var staged_total: u32 = 0;

    // Track dotfiles-deployed paths
    for (deploy_result.tracked) |path| {
        const newly_tracked = !(try containsLine(allocator, io, tracked_paths_path, path));
        if (dry_run) {
            if (newly_tracked) try out.print("  would track: {s}\n", .{path});
        } else {
            if (newly_tracked) {
                try appendLine(io, tracked_paths_path, path);
                try out.print("  tracked: {s}\n", .{path});
            }
            if (repo_p7_opt) |repo| {
                staged_total += try stageTrackedPath(allocator, io, repo, worktree_path_p7, path, out);
            }
        }
    }

    // Track package config_paths for installed packages
    for (catalog.packages) |pkg| {
        var in_profile = false;
        for (host_profiles.items) |profile| {
            if (pkg.hasProfile(profile)) { in_profile = true; break; }
        }
        if (!in_profile) continue;
        if (!pkgmgr.isInstalled(io, environ_map, pkg)) continue;
        for (pkg.config_paths) |raw_path| {
            const path = if (std.mem.startsWith(u8, raw_path, "~/"))
                try std.fmt.allocPrint(allocator, "{s}/{s}", .{ home, raw_path[2..] })
            else
                try allocator.dupe(u8, raw_path);
            defer allocator.free(path);
            std.Io.Dir.cwd().access(io, path, .{}) catch continue;
            const newly_tracked = !(try containsLine(allocator, io, tracked_paths_path, path));
            if (dry_run) {
                if (newly_tracked) try out.print("  would track: {s}\n", .{path});
            } else {
                if (newly_tracked) {
                    try appendLine(io, tracked_paths_path, path);
                    try out.print("  tracked: {s}\n", .{path});
                }
                if (repo_p7_opt) |repo| {
                    staged_total += try stageTrackedPath(allocator, io, repo, worktree_path_p7, path, out);
                }
            }
            break;
        }
    }

    if (!dry_run and repo_p7_opt != null) {
        try out.print("  staged to index: {d} files\n", .{staged_total});
    }

    // Phase 8: Reboot/re-login prompt
    try out.print("\nphase 8: summary\n", .{});
    if (groups_added) {
        try out.print("  groups added — re-login to apply, or: newgrp docker\n", .{});
    }
    if (shell_changed) {
        try out.print("  shell changed — re-login to apply\n", .{});
    }
    try out.print("\n  manual steps:\n", .{});
    try out.print("    - op signin           (1Password)\n", .{});
    try out.print("    - gcloud auth login   (Google Cloud)\n", .{});
    try out.print("    - aws configure       (AWS)\n", .{});
    try out.print("    - edit ~/.gitconfig   (name + email)\n", .{});

    try out.print("\nbootstrap complete. run: desperta doctor\n", .{});
    return 0;
}

fn commandService(
    args: *std.process.Args.Iterator,
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
) !u8 {
    const subcmd = args.next() orelse {
        try out.print("usage: desperta service <install|status|enable>\n", .{});
        return 1;
    };
    const flags = Flags.parse(args);
    const dry_run = !flags.apply;

    const sysinfo = try detect.detect(allocator, io, environ_map);
    defer sysinfo.deinit(allocator);

    var m = try manifest.load(allocator, io, environ_map);
    defer m.deinit(allocator);

    var catalog = try packages.load(allocator, io);
    defer catalog.deinit(allocator);

    const hostname = flags.host orelse sysinfo.hostname;

    var host_profiles = std.ArrayList([]const u8).empty;
    defer host_profiles.deinit(allocator);
    if (m.findHost(hostname)) |hc| {
        for (hc.profiles) |p| try host_profiles.append(allocator, p);
    } else {
        try host_profiles.append(allocator, "base");
    }

    if (eql(subcmd, "install")) {
        // Enable all services for active profiles
        const username = environ_map.get("USER") orelse environ_map.get("LOGNAME") orelse
        std.fs.path.basename(environ_map.get("HOME") orelse "");
        for (catalog.packages) |pkg| {
            var in_profile = false;
            for (host_profiles.items) |profile| {
                if (pkg.hasProfile(profile)) { in_profile = true; break; }
            }
            if (!in_profile) continue;
            if (!platformMatches(sysinfo.os_id, pkg)) continue;

            if (pkg.service_system) |svc| {
                _ = try services.enableSystemService(io, allocator, out, svc, dry_run);
            }
            if (pkg.service_user) |svc| {
                _ = try services.enableUserService(io, allocator, out, svc, environ_map, dry_run);
            }
            for (pkg.groups) |grp| {
                _ = try services.addUserToGroup(io, allocator, out, grp, username, dry_run);
            }
        }
    } else if (eql(subcmd, "status")) {
        // Show status table for all services in active profiles
        try out.print("{s:<20} {s:<10} {s}\n", .{ "service", "scope", "status" });
        try out.print("{s}\n", .{"─" ** 42});
        for (catalog.packages) |pkg| {
            var in_profile = false;
            for (host_profiles.items) |profile| {
                if (pkg.hasProfile(profile)) { in_profile = true; break; }
            }
            if (!in_profile) continue;
            if (!platformMatches(sysinfo.os_id, pkg)) continue;

            if (pkg.service_system) |svc| {
                const status = getServiceStatus(io, allocator, svc, false) catch "unknown";
                try out.print("{s:<20} {s:<10} {s}\n", .{ svc, "system", status });
            }
            if (pkg.service_user) |svc| {
                const status = getServiceStatus(io, allocator, svc, true) catch "unknown";
                try out.print("{s:<20} {s:<10} {s}\n", .{ svc, "user", status });
            }
        }
    } else if (eql(subcmd, "enable")) {
        const name = args.next() orelse {
            try out.print("usage: desperta service enable [--system] <name>\n", .{});
            return 1;
        };
        if (flags.system) {
            _ = try services.enableSystemService(io, allocator, out, name, dry_run);
        } else {
            _ = try services.enableUserService(io, allocator, out, name, environ_map, dry_run);
        }
    } else {
        try out.print("unknown service subcommand: {s}\n", .{subcmd});
        try out.print("usage: desperta service <install|status|enable>\n", .{});
        return 1;
    }

    return 0;
}

fn getServiceStatus(
    io: std.Io,
    allocator: std.mem.Allocator,
    name: []const u8,
    user_scope: bool,
) ![]const u8 {
    var argv = std.ArrayList([]const u8).empty;
    defer argv.deinit(allocator);

    try argv.append(allocator, "systemctl");
    if (user_scope) try argv.append(allocator, "--user");
    try argv.append(allocator, "is-active");
    try argv.append(allocator, name);

    var child = std.process.spawn(io, .{ .argv = argv.items }) catch return "error";
    const term = child.wait(io) catch return "error";
    return switch (term) {
        .exited => |code| if (code == 0) "active" else "inactive",
        else => "unknown",
    };
}

fn commandMigrate(
    args: *std.process.Args.Iterator,
    out: *std.Io.Writer,
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
) !u8 {
    const flags = Flags.parse(args);

    const from = flags.from orelse {
        try out.print("missing --from <host>\n", .{});
        return 1;
    };
    const to = flags.to orelse {
        try out.print("missing --to <host>\n", .{});
        return 1;
    };

    var m = try manifest.load(allocator, io, environ_map);
    defer m.deinit(allocator);

    const src = m.findHost(from) orelse {
        try out.print("unknown host: {s}\n", .{from});
        return 1;
    };
    const dst = m.findHost(to) orelse {
        try out.print("unknown host: {s} (not in manifest, will be created on init)\n", .{to});
        // Not fatal — destination may be a new machine not yet in the manifest.
        try out.print("migration plan: {s} -> {s}\n\n", .{ from, to });
        try out.print("source platform: {s}  profiles:", .{src.platform});
        for (src.profiles) |p| try out.print(" {s}", .{p});
        try out.print("\ndestination platform: unknown (new host)\n\n", .{});
        try migratePrintSteps(out, from, to, src.profiles, &.{});
        return 0;
    };

    try out.print("migration plan: {s} -> {s}\n\n", .{ from, to });

    try out.print("source:      platform={s}  profiles:", .{src.platform});
    for (src.profiles) |p| try out.print(" {s}", .{p});
    try out.print("\n", .{});

    try out.print("destination: platform={s}  profiles:", .{dst.platform});
    for (dst.profiles) |p| try out.print(" {s}", .{p});
    try out.print("\n\n", .{});

    // Profile diff.
    var profile_diff = false;
    for (src.profiles) |sp| {
        var found = false;
        for (dst.profiles) |dp| {
            if (std.mem.eql(u8, sp, dp)) { found = true; break; }
        }
        if (!found) {
            if (!profile_diff) { try out.print("profile diff:\n", .{}); profile_diff = true; }
            try out.print("  - {s} (source only)\n", .{sp});
        }
    }
    for (dst.profiles) |dp| {
        var found = false;
        for (src.profiles) |sp| {
            if (std.mem.eql(u8, dp, sp)) { found = true; break; }
        }
        if (!found) {
            if (!profile_diff) { try out.print("profile diff:\n", .{}); profile_diff = true; }
            try out.print("  + {s} (destination only)\n", .{dp});
        }
    }
    if (!profile_diff) try out.print("profiles: identical\n", .{});
    try out.print("\n", .{});

    // Tracked paths count.
    const tracked_paths_file = if (m.policy.tracked_paths) |tp| tp else "config/tracked-paths.txt";
    const tracked_data = std.Io.Dir.cwd().readFileAlloc(io, tracked_paths_file, allocator, .limited(64 * 1024)) catch null;
    defer if (tracked_data) |d| allocator.free(d);

    if (tracked_data) |td| {
        var count: usize = 0;
        var liter = std.mem.splitScalar(u8, td, '\n');
        while (liter.next()) |ln| {
            const t = std.mem.trim(u8, ln, " \t\r\n");
            if (t.len > 0 and t[0] != '#') count += 1;
        }
        try out.print("tracked files: {d}\n\n", .{count});
    }

    try migratePrintSteps(out, from, to, src.profiles, dst.profiles);
    return 0;
}

fn migratePrintSteps(
    out: *std.Io.Writer,
    from: []const u8,
    to: []const u8,
    src_profiles: []const []const u8,
    dst_profiles: []const []const u8,
) !void {
    _ = src_profiles;
    _ = dst_profiles;
    try out.print("steps:\n", .{});
    try out.print("  1. on {s}: run desperta snapshot\n", .{from});
    try out.print("  2. on {s}: run desperta init --host {s}\n", .{ to, to });
    try out.print("  3. transfer tracked files to {s} (git push/pull or manual copy)\n", .{to});
    try out.print("  4. on {s}: run desperta sync --apply\n", .{to});
    try out.print("  5. on {s}: run desperta doctor\n", .{to});
}

// --- Path resolution ---

fn resolveRepoPath(
    allocator: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
    cfg: *const config.Config,
) ![]const u8 {
    // Item 4: prefer runtime config over env vars.
    if (cfg.repo_path) |p| return allocator.dupe(u8, p);
    if (environ_map.get("DESPERTA_REPO_PATH")) |v| return allocator.dupe(u8, v);
    if (environ_map.get("XDG_STATE_HOME")) |v| {
        return std.fmt.allocPrint(allocator, "{s}/despertaferro/repo.git", .{v});
    }
    if (environ_map.get("HOME")) |v| {
        return std.fmt.allocPrint(allocator, "{s}/.local/state/despertaferro/repo.git", .{v});
    }
    return error.MissingHome;
}

fn resolveWorktreePath(
    allocator: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
    cfg: *const config.Config,
) ![]const u8 {
    // Item 4: prefer runtime config over env vars.
    if (cfg.worktree) |p| return allocator.dupe(u8, p);
    if (environ_map.get("DESPERTA_WORKTREE")) |v| return allocator.dupe(u8, v);
    if (environ_map.get("HOME")) |v| return allocator.dupe(u8, v);
    return error.MissingHome;
}

fn resolveSnapshotBase(allocator: std.mem.Allocator, environ_map: *const std.process.Environ.Map) ![]const u8 {
    if (environ_map.get("XDG_CACHE_HOME")) |v| {
        return std.fmt.allocPrint(allocator, "{s}/despertaferro/snapshots", .{v});
    }
    if (environ_map.get("HOME")) |v| {
        return std.fmt.allocPrint(allocator, "{s}/.cache/despertaferro/snapshots", .{v});
    }
    return error.MissingHome;
}

// --- Init helpers ---

fn initBareRepo(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo_path: []const u8,
    hostname: []const u8,
) !void {
    const subdirs = [_][]const u8{
        "objects/info",
        "objects/pack",
        "refs/heads",
        "refs/tags",
    };
    for (subdirs) |sub| {
        const p = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ repo_path, sub });
        defer allocator.free(p);
        try std.Io.Dir.cwd().createDirPath(io, p);
    }

    const branch = try std.fmt.allocPrint(allocator, "ref: refs/heads/hosts/{s}\n", .{hostname});
    defer allocator.free(branch);

    try writeRepoFile(allocator, io, repo_path, "HEAD", branch);
    try writeRepoFile(allocator, io, repo_path, "config", "[core]\n\tbare = true\n\trepositoryformatversion = 0\n\tfilemode = true\n");
    try writeRepoFile(allocator, io, repo_path, "description", "despertaferro configuration repository\n");
}

fn writeRepoFile(allocator: std.mem.Allocator, io: std.Io, repo_path: []const u8, name: []const u8, content: []const u8) !void {
    const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ repo_path, name });
    defer allocator.free(path);
    var f = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer f.close(io);
    try f.writePositionalAll(io, content, 0);
}

fn writeRuntimeConfig(io: std.Io, path: []const u8, repo_path: []const u8, worktree: []const u8) !void {
    var f = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer f.close(io);

    var buf: [1024]u8 = undefined;
    var w = f.writer(io, &buf);
    try w.interface.print("[runtime]\n", .{});
    try w.interface.print("repo_path = \"{s}\"\n", .{repo_path});
    try w.interface.print("work_tree = \"{s}\"\n", .{worktree});
    try w.interface.flush();
}

// --- Denylist helpers ---

// Item 1: check if a path matches any denylist pattern.
fn getCurrentLoginShell(allocator: std.mem.Allocator, io: std.Io, username: []const u8) !?[]const u8 {
    const data = std.Io.Dir.cwd().readFileAlloc(io, "/etc/passwd", allocator, .limited(1024 * 1024)) catch return null;
    defer allocator.free(data);

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0 or line[0] == '#') continue;
        var parts = std.mem.splitScalar(u8, line, ':');
        const user = parts.next() orelse continue;
        if (!std.mem.eql(u8, user, username)) continue;
        _ = parts.next(); _ = parts.next(); _ = parts.next();
        _ = parts.next(); _ = parts.next();
        const shell = parts.next() orelse continue;
        return try allocator.dupe(u8, shell);
    }
    return null;
}

fn parseChshTarget(cmd: []const u8) ?[]const u8 {
    const idx = std.mem.indexOf(u8, cmd, "-s ") orelse return null;
    var rest = cmd[idx + 3 ..];
    while (rest.len > 0 and (rest[0] == ' ' or rest[0] == '\t')) rest = rest[1..];
    const end = std.mem.indexOfAny(u8, rest, " \t") orelse rest.len;
    return rest[0..end];
}

fn stageTrackedPath(
    allocator: std.mem.Allocator,
    io: std.Io,
    repo: git_backend.BareRepository,
    worktree_path: []const u8,
    path: []const u8,
    out: *std.Io.Writer,
) !u32 {
    var rel_path: []const u8 = path;
    if (std.fs.path.isAbsolute(path)) {
        if (!std.mem.startsWith(u8, path, worktree_path)) return 0;
        if (path.len == worktree_path.len) return 0;
        const offset: usize = if (path[worktree_path.len] == '/') worktree_path.len + 1 else worktree_path.len;
        rel_path = path[offset..];
    }
    if (rel_path.len == 0) return 0;

    const full = try std.fs.path.join(allocator, &.{ worktree_path, rel_path });
    defer allocator.free(full);

    const stat = std.Io.Dir.cwd().statFile(io, full, .{}) catch |err| switch (err) {
        error.FileNotFound => return 0,
        else => return err,
    };

    if (stat.kind == .file) {
        if (try isDenylisted(allocator, io, rel_path)) return 0;
        git_backend.addPathToIndex(allocator, io, repo, worktree_path, rel_path) catch |err| {
            try out.print("    stage error: {s}: {any}\n", .{ rel_path, err });
            return 0;
        };
        return 1;
    }

    if (stat.kind != .directory) return 0;

    var dir = std.Io.Dir.cwd().openDir(io, full, .{ .iterate = true }) catch return 0;
    defer dir.close(io);

    var walker = try dir.walk(allocator);
    defer walker.deinit();

    var count: u32 = 0;
    while (try walker.next(io)) |entry| {
        if (entry.kind != .file) continue;
        const file_rel = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ rel_path, entry.path });
        defer allocator.free(file_rel);

        if (try isDenylisted(allocator, io, file_rel)) continue;

        git_backend.addPathToIndex(allocator, io, repo, worktree_path, file_rel) catch |err| {
            try out.print("    stage error: {s}: {any}\n", .{ file_rel, err });
            continue;
        };
        count += 1;
    }
    return count;
}

fn isDenylisted(allocator: std.mem.Allocator, io: std.Io, path: []const u8) !bool {
    var file = std.Io.Dir.cwd().openFile(io, denylist_path, .{}) catch |err| switch (err) {
        error.FileNotFound => return false,
        else => return err,
    };
    defer file.close(io);

    const stat = try file.stat(io);
    if (stat.size > 1024 * 1024) return error.FileTooBig;
    const len: usize = @intCast(stat.size);
    const data = try allocator.alloc(u8, len);
    defer allocator.free(data);
    const bytes_read = try file.readPositionalAll(io, data, 0);

    const basename = std.fs.path.basename(path);

    var lines = std.mem.splitScalar(u8, data[0..bytes_read], '\n');
    while (lines.next()) |line| {
        const pattern = std.mem.trim(u8, line, " \t\r\n");
        if (pattern.len == 0 or pattern[0] == '#') continue;
        if (matchGlob(pattern, path) or matchGlob(pattern, basename)) return true;
    }
    return false;
}

// Item 1: simple glob matcher: * matches non-/ chars, ** matches anything including /.
fn matchGlob(pattern: []const u8, text: []const u8) bool {
    if (pattern.len == 0) return text.len == 0;

    if (std.mem.startsWith(u8, pattern, "**")) {
        const rest = if (pattern.len > 2 and pattern[2] == '/') pattern[3..] else pattern[2..];
        var i: usize = 0;
        while (i <= text.len) : (i += 1) {
            if (matchGlob(rest, text[i..])) return true;
        }
        return false;
    }

    if (pattern[0] == '*') {
        const rest = pattern[1..];
        var i: usize = 0;
        while (i <= text.len) : (i += 1) {
            if (i > 0 and text[i - 1] == '/') break;
            if (matchGlob(rest, text[i..])) return true;
        }
        return false;
    }

    if (text.len == 0) return false;
    if (pattern[0] != text[0]) return false;
    return matchGlob(pattern[1..], text[1..]);
}

// --- File helpers ---

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

fn fileExists(io: std.Io, path: []const u8) bool {
    std.Io.Dir.cwd().access(io, path, .{}) catch return false;
    return true;
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn platformMatches(os_id: []const u8, pkg: packages.Package) bool {
    if (pkg.hasPlatform(os_id)) return true;
    const is_linux = !std.mem.eql(u8, os_id, "macos") and !std.mem.eql(u8, os_id, "darwin");
    if (is_linux and pkg.hasPlatform("linux")) return true;
    if ((std.mem.eql(u8, os_id, "macos") or std.mem.eql(u8, os_id, "darwin")) and pkg.hasPlatform("macos")) return true;
    return false;
}

fn printHelp(out: *std.Io.Writer) !void {
    try out.print(
        \\desperta - personal configuration runtime
        \\
        \\config management:
        \\  desperta status
        \\  desperta track [--json] <path>...
        \\  desperta ignore <pattern>...
        \\  desperta sync [--apply] [--json]
        \\  desperta snapshot
        \\  desperta migrate --from <host> --to <host>
        \\
        \\package management:
        \\  desperta list [--host <profile>]
        \\  desperta install [--apply] [--host <profile>]
        \\  desperta bootstrap [--apply] [--profile <name>] [--from <host>|--adopt <host>] [--force]
        \\
        \\services:
        \\  desperta service install [--apply]
        \\  desperta service status
        \\  desperta service enable [--system] <name>
        \\
        \\maintenance:
        \\  desperta init [--host <name>]
        \\  desperta doctor
        \\
        \\flags:
        \\  --apply           execute changes (default is dry-run)
        \\  --json            structured JSON output
        \\  --host <name>     specify host name (lookup in manifest)
        \\  --profile <name>  bypass manifest, use a specific profile directly
        \\  --from <host>     copy dotfile templates from another host
        \\  --adopt <host>    take ownership of another host's identity
        \\  --force           overwrite existing dotfiles in phase 5
        \\  --system          target system scope (vs user scope)
        \\
        \\release build:
        \\  zig build -Dtarget=x86_64-linux-musl -Doptimize=ReleaseSafe
        \\
    , .{});
}
