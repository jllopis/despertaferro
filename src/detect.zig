const std = @import("std");
const builtin = @import("builtin");

pub const OsKind = enum { linux, macos, windows, other };

pub const SystemInfo = struct {
    os: OsKind,
    os_id: []const u8,
    os_version: []const u8,
    shell: []const u8,
    hostname: []const u8,

    pub fn deinit(self: SystemInfo, allocator: std.mem.Allocator) void {
        allocator.free(self.os_id);
        allocator.free(self.os_version);
        allocator.free(self.shell);
        allocator.free(self.hostname);
    }
};

pub fn detect(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
) !SystemInfo {
    const os_kind: OsKind = switch (builtin.os.tag) {
        .linux => .linux,
        .macos => .macos,
        .windows => .windows,
        else => .other,
    };

    const os_id, const os_version = switch (builtin.os.tag) {
        .linux => blk: {
            const info = readOsRelease(allocator, io) catch OsReleaseInfo{
                .id = try allocator.dupe(u8, "linux"),
                .version = try allocator.dupe(u8, ""),
            };
            break :blk .{ info.id, info.version };
        },
        .macos => .{ try allocator.dupe(u8, "macos"), try allocator.dupe(u8, "") },
        .windows => .{ try allocator.dupe(u8, "windows"), try allocator.dupe(u8, "") },
        else => .{ try allocator.dupe(u8, "unknown"), try allocator.dupe(u8, "") },
    };
    errdefer allocator.free(os_id);
    errdefer allocator.free(os_version);

    const shell_raw = environ_map.get("SHELL") orelse "/bin/bash";
    const shell = try allocator.dupe(u8, std.fs.path.basename(shell_raw));
    errdefer allocator.free(shell);

    var host_buf: [std.posix.HOST_NAME_MAX]u8 = undefined;
    const hostname_slice = try std.posix.gethostname(&host_buf);
    const hostname = try allocator.dupe(u8, hostname_slice);

    return .{
        .os = os_kind,
        .os_id = os_id,
        .os_version = os_version,
        .shell = shell,
        .hostname = hostname,
    };
}

const OsReleaseInfo = struct {
    id: []const u8,
    version: []const u8,
};

fn readOsRelease(allocator: std.mem.Allocator, io: std.Io) !OsReleaseInfo {
    const data = try std.Io.Dir.cwd().readFileAlloc(io, "/etc/os-release", allocator, .limited(4 * 1024));
    defer allocator.free(data);

    var id: ?[]const u8 = null;
    var version: ?[]const u8 = null;
    errdefer {
        if (id) |s| allocator.free(s);
        if (version) |s| allocator.free(s);
    }

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;
        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const key = trimmed[0..eq];
        const val = unquote(std.mem.trim(u8, trimmed[eq + 1 ..], " \t"));

        if (std.mem.eql(u8, key, "ID") and id == null) {
            id = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "VERSION_ID") and version == null) {
            version = try allocator.dupe(u8, val);
        }
    }

    return .{
        .id = id orelse try allocator.dupe(u8, "linux"),
        .version = version orelse try allocator.dupe(u8, ""),
    };
}

fn unquote(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') return s[1 .. s.len - 1];
    return s;
}

test "detect returns something" {
    const io = std.Io.null_io;
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("SHELL", "/bin/zsh");
    const info = try detect(std.testing.allocator, io, &env);
    defer info.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("zsh", info.shell);
    try std.testing.expect(info.hostname.len > 0);
}
