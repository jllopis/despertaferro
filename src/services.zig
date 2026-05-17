const std = @import("std");

pub fn enableUserService(
    io: std.Io,
    allocator: std.mem.Allocator,
    out: *std.Io.Writer,
    name: []const u8,
    environ_map: *const std.process.Environ.Map,
    dry_run: bool,
) !bool {
    try out.print("\n[service --user {s}] enable + start\n", .{name});
    if (dry_run) return true;
    if (environ_map.get("XDG_RUNTIME_DIR") == null) {
        const uname = environ_map.get("USER") orelse environ_map.get("LOGNAME") orelse
            std.fs.path.basename(environ_map.get("HOME") orelse "");
        try out.print("  warn: user session not active — run 'loginctl enable-linger {s}' and re-login\n", .{
            if (uname.len > 0) uname else "$(whoami)",
        });
        return false;
    }
    const ok1 = try runArgv(io, allocator, out, &.{ "systemctl", "--user", "enable", name });
    const ok2 = try runArgv(io, allocator, out, &.{ "systemctl", "--user", "start", name });
    return ok1 and ok2;
}

pub fn enableSystemService(
    io: std.Io,
    allocator: std.mem.Allocator,
    out: *std.Io.Writer,
    name: []const u8,
    dry_run: bool,
) !bool {
    try out.print("\n[service --system {s}] enable + start\n", .{name});
    if (dry_run) return true;
    const ok1 = try runArgv(io, allocator, out, &.{ "sudo", "systemctl", "enable", name });
    const ok2 = try runArgv(io, allocator, out, &.{ "sudo", "systemctl", "start", name });
    return ok1 and ok2;
}

pub fn addUserToGroup(
    io: std.Io,
    allocator: std.mem.Allocator,
    out: *std.Io.Writer,
    group: []const u8,
    username: []const u8,
    dry_run: bool,
) !bool {
    try out.print("\n[group] add {s} to {s}\n", .{ username, group });
    if (dry_run) return true;
    return runArgv(io, allocator, out, &.{ "sudo", "usermod", "-aG", group, username });
}

pub fn rebuildFontCache(
    io: std.Io,
    allocator: std.mem.Allocator,
    out: *std.Io.Writer,
    dry_run: bool,
) !bool {
    try out.print("\n[fc-cache] rebuilding font cache\n", .{});
    if (dry_run) return true;
    return runArgv(io, allocator, out, &.{ "fc-cache", "-f" });
}

pub fn runPostCmd(
    io: std.Io,
    allocator: std.mem.Allocator,
    out: *std.Io.Writer,
    cmd: []const u8,
    environ_map: *const std.process.Environ.Map,
    dry_run: bool,
) !bool {
    const expanded = try expandEnv(allocator, cmd, environ_map);
    defer allocator.free(expanded);

    try out.print("\n[post-cmd] {s}\n", .{expanded});
    if (dry_run) return true;

    return runArgv(io, allocator, out, &.{ "/bin/sh", "-c", expanded });
}

fn expandEnv(allocator: std.mem.Allocator, s: []const u8, env: *const std.process.Environ.Map) ![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);
    var i: usize = 0;
    while (i < s.len) {
        if (s[i] == '$' and i + 1 < s.len) {
            i += 1;
            var end = i;
            while (end < s.len and (std.ascii.isAlphanumeric(s[end]) or s[end] == '_')) end += 1;
            const var_name = s[i..end];
            if (env.get(var_name)) |val| {
                try out.appendSlice(allocator, val);
            } else {
                try out.append(allocator, '$');
                try out.appendSlice(allocator, var_name);
            }
            i = end;
        } else {
            try out.append(allocator, s[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(allocator);
}

fn runArgv(
    io: std.Io,
    allocator: std.mem.Allocator,
    out: *std.Io.Writer,
    argv: []const []const u8,
) !bool {
    _ = allocator;
    try out.flush();
    var child = std.process.spawn(io, .{ .argv = argv }) catch |err| {
        try out.print("  error: spawn failed: {any}\n", .{err});
        return false;
    };
    const term = child.wait(io) catch |err| {
        try out.print("  error: wait failed: {any}\n", .{err});
        return false;
    };
    switch (term) {
        .exited => |code| if (code != 0) {
            try out.print("  error: exited with code {d}\n", .{code});
            return false;
        },
        else => {
            try out.print("  error: terminated abnormally\n", .{});
            return false;
        },
    }
    return true;
}

test "expandEnv substitutes known variables" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("HOME", "/home/user");
    try env.put("USER", "user");

    const out = try expandEnv(std.testing.allocator, "chmod 700 $HOME/.gnupg", &env);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("chmod 700 /home/user/.gnupg", out);
}

test "expandEnv leaves unknown variables intact" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    const out = try expandEnv(std.testing.allocator, "echo $UNKNOWN", &env);
    defer std.testing.allocator.free(out);
    try std.testing.expectEqualStrings("echo $UNKNOWN", out);
}
