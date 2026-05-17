const std = @import("std");

pub const RuntimeSection = struct {
    work_tree: ?[]const u8 = null,
    state_dir: ?[]const u8 = null,
    repo_path: ?[]const u8 = null,
    config_dir: ?[]const u8 = null,
    cache_dir: ?[]const u8 = null,

    pub fn deinit(self: RuntimeSection, allocator: std.mem.Allocator) void {
        if (self.work_tree) |s| allocator.free(s);
        if (self.state_dir) |s| allocator.free(s);
        if (self.repo_path) |s| allocator.free(s);
        if (self.config_dir) |s| allocator.free(s);
        if (self.cache_dir) |s| allocator.free(s);
    }
};

pub const GitSection = struct {
    // Optional. Where `desperta sync` pushes this host's dotfiles branch.
    // The branch is always `hosts/<hostname>` — no manifest field controls it.
    remote: ?[]const u8 = null,
    use_git_binary: bool = false,

    pub fn deinit(self: GitSection, allocator: std.mem.Allocator) void {
        if (self.remote) |s| allocator.free(s);
    }
};

pub const PolicySection = struct {
    default_sync_mode: ?[]const u8 = null,
    auto_track_new_files: bool = false,
    auto_commit: bool = false,
    auto_push: bool = false,
    require_snapshot_before_apply: bool = true,
    denylist: ?[]const u8 = null,
    tracked_paths: ?[]const u8 = null,

    pub fn deinit(self: PolicySection, allocator: std.mem.Allocator) void {
        if (self.default_sync_mode) |s| allocator.free(s);
        if (self.denylist) |s| allocator.free(s);
        if (self.tracked_paths) |s| allocator.free(s);
    }
};

pub const HostConfig = struct {
    name: []const u8,
    platform: []const u8,
    profiles: []const []const u8,

    pub fn deinit(self: HostConfig, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        allocator.free(self.platform);
        for (self.profiles) |p| allocator.free(p);
        allocator.free(self.profiles);
    }
};

pub const Manifest = struct {
    schema_version: u32 = 0,
    name: ?[]const u8 = null,
    purpose: ?[]const u8 = null,
    runtime: RuntimeSection = .{},
    git: GitSection = .{},
    policy: PolicySection = .{},
    hosts: ?[]HostConfig = null,

    pub fn deinit(self: *Manifest, allocator: std.mem.Allocator) void {
        if (self.name) |s| allocator.free(s);
        if (self.purpose) |s| allocator.free(s);
        self.runtime.deinit(allocator);
        self.git.deinit(allocator);
        self.policy.deinit(allocator);
        if (self.hosts) |hs| {
            for (hs) |h| h.deinit(allocator);
            allocator.free(hs);
        }
        self.* = .{};
    }

    pub fn findHost(self: Manifest, name: []const u8) ?HostConfig {
        const hs = self.hosts orelse return null;
        for (hs) |h| {
            if (std.mem.eql(u8, h.name, name)) return h;
        }
        return null;
    }
};

pub fn load(
    allocator: std.mem.Allocator,
    io: std.Io,
    environ_map: *const std.process.Environ.Map,
) !Manifest {
    const data = std.Io.Dir.cwd().readFileAlloc(io, "desperta.toml", allocator, .limited(64 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    defer allocator.free(data);
    return parse(allocator, environ_map, data);
}

pub fn expandVars(
    allocator: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    input: []const u8,
) error{OutOfMemory}![]u8 {
    var out = std.ArrayList(u8).empty;
    errdefer out.deinit(allocator);

    var i: usize = 0;
    while (i < input.len) {
        if (i + 1 < input.len and input[i] == '$' and input[i + 1] == '{') {
            var depth: usize = 1;
            var j = i + 2;
            while (j < input.len and depth > 0) : (j += 1) {
                if (input[j] == '{') depth += 1;
                if (input[j] == '}') depth -= 1;
            }
            const expanded = try expandExpr(allocator, env, input[i + 2 .. j - 1]);
            defer allocator.free(expanded);
            try out.appendSlice(allocator, expanded);
            i = j;
        } else {
            try out.append(allocator, input[i]);
            i += 1;
        }
    }
    return out.toOwnedSlice(allocator);
}

fn expandExpr(
    allocator: std.mem.Allocator,
    env: *const std.process.Environ.Map,
    expr: []const u8,
) error{OutOfMemory}![]u8 {
    if (std.mem.indexOf(u8, expr, ":-")) |sep| {
        const varname = expr[0..sep];
        const default_expr = expr[sep + 2 ..];
        if (env.get(varname)) |val| return allocator.dupe(u8, val);
        return expandVars(allocator, env, default_expr);
    }
    if (env.get(expr)) |val| return allocator.dupe(u8, val);
    return allocator.dupe(u8, "");
}

fn parseInlineArray(allocator: std.mem.Allocator, s: []const u8) ![][]const u8 {
    const trimmed = std.mem.trim(u8, s, " \t");
    if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']')
        return &.{};

    var result = std.ArrayList([]const u8).empty;
    errdefer {
        for (result.items) |item| allocator.free(item);
        result.deinit(allocator);
    }

    var iter = std.mem.splitScalar(u8, trimmed[1 .. trimmed.len - 1], ',');
    while (iter.next()) |item_raw| {
        const item = std.mem.trim(u8, item_raw, " \t\"");
        if (item.len == 0) continue;
        try result.append(allocator, try allocator.dupe(u8, item));
    }
    return result.toOwnedSlice(allocator);
}

fn unquote(s: []const u8) []const u8 {
    if (s.len >= 2 and s[0] == '"' and s[s.len - 1] == '"') return s[1 .. s.len - 1];
    return s;
}

fn parseBool(s: []const u8) bool {
    return std.mem.eql(u8, s, "true");
}

fn flushHost(
    allocator: std.mem.Allocator,
    cur_name: *?[]const u8,
    cur_platform: *?[]const u8,
    cur_profiles: *std.ArrayList([]const u8),
    hosts: *std.ArrayList(HostConfig),
) !void {
    const profiles_slice = try cur_profiles.toOwnedSlice(allocator);
    errdefer {
        for (profiles_slice) |p| allocator.free(p);
        allocator.free(profiles_slice);
    }
    try hosts.append(allocator, .{
        .name = cur_name.* orelse try allocator.dupe(u8, ""),
        .platform = cur_platform.* orelse try allocator.dupe(u8, ""),
        .profiles = profiles_slice,
    });
    cur_name.* = null;
    cur_platform.* = null;
}

fn parse(
    allocator: std.mem.Allocator,
    environ_map: *const std.process.Environ.Map,
    data: []const u8,
) !Manifest {
    var m = Manifest{};
    errdefer m.deinit(allocator);

    const Section = enum { root, runtime, git, policy, hosts };
    var section: Section = .root;

    var cur_name: ?[]const u8 = null;
    var cur_platform: ?[]const u8 = null;
    var cur_profiles = std.ArrayList([]const u8).empty;
    var in_host = false;

    var hosts = std.ArrayList(HostConfig).empty;
    errdefer {
        for (hosts.items) |h| h.deinit(allocator);
        hosts.deinit(allocator);
    }

    // Always clean up any partially-built host fields.
    defer {
        if (cur_name) |s| allocator.free(s);
        if (cur_platform) |s| allocator.free(s);
        for (cur_profiles.items) |p| allocator.free(p);
        cur_profiles.deinit(allocator);
    }

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (std.mem.startsWith(u8, trimmed, "[[")) {
            if (in_host) {
                try flushHost(allocator, &cur_name, &cur_platform, &cur_profiles, &hosts);
                in_host = false;
            }
            if (std.mem.eql(u8, trimmed, "[[hosts]]")) {
                section = .hosts;
                in_host = true;
            }
            continue;
        }

        if (trimmed[0] == '[') {
            if (in_host) {
                try flushHost(allocator, &cur_name, &cur_platform, &cur_profiles, &hosts);
                in_host = false;
            }
            section = if (std.mem.eql(u8, trimmed, "[runtime]"))
                .runtime
            else if (std.mem.eql(u8, trimmed, "[git]"))
                .git
            else if (std.mem.eql(u8, trimmed, "[policy]"))
                .policy
            else
                .root;
            continue;
        }

        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const key = std.mem.trim(u8, trimmed[0..eq], " \t");
        const raw_val = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");

        switch (section) {
            .root => {
                if (std.mem.eql(u8, key, "schema_version")) {
                    m.schema_version = std.fmt.parseInt(u32, raw_val, 10) catch 0;
                } else if (std.mem.eql(u8, key, "name")) {
                    if (m.name) |s| allocator.free(s);
                    m.name = try allocator.dupe(u8, unquote(raw_val));
                } else if (std.mem.eql(u8, key, "purpose")) {
                    if (m.purpose) |s| allocator.free(s);
                    m.purpose = try allocator.dupe(u8, unquote(raw_val));
                }
            },
            .runtime => {
                const val = try expandVars(allocator, environ_map, unquote(raw_val));
                const dest = if (std.mem.eql(u8, key, "work_tree"))
                    &m.runtime.work_tree
                else if (std.mem.eql(u8, key, "state_dir"))
                    &m.runtime.state_dir
                else if (std.mem.eql(u8, key, "repo_path"))
                    &m.runtime.repo_path
                else if (std.mem.eql(u8, key, "config_dir"))
                    &m.runtime.config_dir
                else if (std.mem.eql(u8, key, "cache_dir"))
                    &m.runtime.cache_dir
                else
                    null;
                if (dest) |d| {
                    if (d.*) |s| allocator.free(s);
                    d.* = val;
                } else {
                    allocator.free(val);
                }
            },
            .git => {
                const val = unquote(raw_val);
                if (std.mem.eql(u8, key, "remote")) {
                    if (m.git.remote) |s| allocator.free(s);
                    m.git.remote = try allocator.dupe(u8, val);
                } else if (std.mem.eql(u8, key, "use_git_binary")) {
                    m.git.use_git_binary = parseBool(val);
                }
                // Older fields (default_branch, host_branch_prefix, base_branch)
                // are silently ignored; the active branch is always hosts/<hostname>.
            },
            .policy => {
                const val = unquote(raw_val);
                if (std.mem.eql(u8, key, "default_sync_mode")) {
                    if (m.policy.default_sync_mode) |s| allocator.free(s);
                    m.policy.default_sync_mode = try allocator.dupe(u8, val);
                } else if (std.mem.eql(u8, key, "auto_track_new_files")) {
                    m.policy.auto_track_new_files = parseBool(val);
                } else if (std.mem.eql(u8, key, "auto_commit")) {
                    m.policy.auto_commit = parseBool(val);
                } else if (std.mem.eql(u8, key, "auto_push")) {
                    m.policy.auto_push = parseBool(val);
                } else if (std.mem.eql(u8, key, "require_snapshot_before_apply")) {
                    m.policy.require_snapshot_before_apply = parseBool(val);
                } else if (std.mem.eql(u8, key, "denylist")) {
                    if (m.policy.denylist) |s| allocator.free(s);
                    m.policy.denylist = try allocator.dupe(u8, val);
                } else if (std.mem.eql(u8, key, "tracked_paths")) {
                    if (m.policy.tracked_paths) |s| allocator.free(s);
                    m.policy.tracked_paths = try allocator.dupe(u8, val);
                }
            },
            .hosts => {
                const val = unquote(raw_val);
                if (std.mem.eql(u8, key, "name")) {
                    if (cur_name) |s| allocator.free(s);
                    cur_name = try allocator.dupe(u8, val);
                } else if (std.mem.eql(u8, key, "platform")) {
                    if (cur_platform) |s| allocator.free(s);
                    cur_platform = try allocator.dupe(u8, val);
                } else if (std.mem.eql(u8, key, "profiles")) {
                    for (cur_profiles.items) |p| allocator.free(p);
                    cur_profiles.clearRetainingCapacity();
                    const items = try parseInlineArray(allocator, raw_val);
                    defer allocator.free(items);
                    try cur_profiles.appendSlice(allocator, items);
                }
                // `branch` is silently ignored — always `hosts/<name>`.
            },
        }
    }

    if (in_host) {
        try flushHost(allocator, &cur_name, &cur_platform, &cur_profiles, &hosts);
    }

    m.hosts = try hosts.toOwnedSlice(allocator);
    return m;
}

test "expandVars resolves simple variable" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("HOME", "/home/test");

    const result = try expandVars(std.testing.allocator, &env, "${HOME}/.config");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("/home/test/.config", result);
}

test "expandVars uses default when variable missing" {
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();
    try env.put("HOME", "/home/test");

    const result = try expandVars(std.testing.allocator, &env, "${XDG_STATE_HOME:-${HOME}/.local/state}/despertaferro");
    defer std.testing.allocator.free(result);
    try std.testing.expectEqualStrings("/home/test/.local/state/despertaferro", result);
}

test "parse full manifest" {
    const data =
        \\schema_version = 1
        \\name = "despertaferro"
        \\purpose = "test"
        \\
        \\[runtime]
        \\work_tree = "/home/user"
        \\repo_path = "/home/user/.local/state/despertaferro/repo.git"
        \\
        \\[git]
        \\remote = "git@github.com:user/repo.git"
        \\use_git_binary = false
        \\
        \\[policy]
        \\auto_commit = true
        \\denylist = "config/denylist.txt"
        \\
        \\[[hosts]]
        \\name = "box1"
        \\platform = "linux"
        \\profiles = ["base", "arch"]
        \\
        \\[[hosts]]
        \\name = "box2"
        \\platform = "macos"
        \\profiles = ["base", "macos"]
    ;
    var env = std.process.Environ.Map.init(std.testing.allocator);
    defer env.deinit();

    var m = try parse(std.testing.allocator, &env, data);
    defer m.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u32, 1), m.schema_version);
    try std.testing.expectEqualStrings("despertaferro", m.name.?);
    try std.testing.expectEqualStrings("/home/user", m.runtime.work_tree.?);
    try std.testing.expectEqualStrings("git@github.com:user/repo.git", m.git.remote.?);
    try std.testing.expect(m.policy.auto_commit);
    try std.testing.expectEqualStrings("config/denylist.txt", m.policy.denylist.?);

    const hs = m.hosts.?;
    try std.testing.expectEqual(@as(usize, 2), hs.len);
    try std.testing.expectEqualStrings("box1", hs[0].name);
    try std.testing.expectEqualStrings("linux", hs[0].platform);
    try std.testing.expectEqual(@as(usize, 2), hs[0].profiles.len);
    try std.testing.expectEqualStrings("arch", hs[0].profiles[1]);
    try std.testing.expectEqualStrings("box2", hs[1].name);
    try std.testing.expectEqualStrings("macos", hs[1].platform);
}
