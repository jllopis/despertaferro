const std = @import("std");

pub const Package = struct {
    id: []const u8,
    description: []const u8,
    profiles: []const []const u8,
    platforms: []const []const u8,
    config_paths: []const []const u8,
    pacman: ?[]const u8,
    aur: ?[]const u8,
    brew: ?[]const u8,
    brew_cask: ?[]const u8,
    check_cmd: ?[]const u8,
    skip: ?[]const u8,
    install_script: ?[]const u8,
    service_user: ?[]const u8,
    service_system: ?[]const u8,
    groups: []const []const u8,
    post_cmd: ?[]const u8,
    font_pkg: bool,

    pub fn deinit(self: Package, allocator: std.mem.Allocator) void {
        allocator.free(self.id);
        allocator.free(self.description);
        for (self.profiles) |p| allocator.free(p);
        allocator.free(self.profiles);
        for (self.platforms) |p| allocator.free(p);
        allocator.free(self.platforms);
        for (self.config_paths) |p| allocator.free(p);
        allocator.free(self.config_paths);
        if (self.pacman) |s| allocator.free(s);
        if (self.aur) |s| allocator.free(s);
        if (self.brew) |s| allocator.free(s);
        if (self.brew_cask) |s| allocator.free(s);
        if (self.check_cmd) |s| allocator.free(s);
        if (self.skip) |s| allocator.free(s);
        if (self.install_script) |s| allocator.free(s);
        if (self.service_user) |s| allocator.free(s);
        if (self.service_system) |s| allocator.free(s);
        for (self.groups) |g| allocator.free(g);
        allocator.free(self.groups);
        if (self.post_cmd) |s| allocator.free(s);
    }

    pub fn binaryCmd(self: Package) []const u8 {
        if (self.check_cmd) |c| return c;
        return self.id;
    }

    pub fn hasProfile(self: Package, profile: []const u8) bool {
        for (self.profiles) |p| {
            if (std.mem.eql(u8, p, profile)) return true;
        }
        return false;
    }

    pub fn hasPlatform(self: Package, platform: []const u8) bool {
        for (self.platforms) |p| {
            if (std.mem.eql(u8, p, platform)) return true;
        }
        return false;
    }
};

pub const Catalog = struct {
    packages: []Package,

    pub fn deinit(self: *Catalog, allocator: std.mem.Allocator) void {
        for (self.packages) |p| p.deinit(allocator);
        allocator.free(self.packages);
        self.* = .{ .packages = &.{} };
    }

    pub fn forProfile(self: Catalog, allocator: std.mem.Allocator, profile: []const u8) ![]const Package {
        var out = std.ArrayList(Package).empty;
        errdefer out.deinit(allocator);
        for (self.packages) |p| {
            if (p.hasProfile(profile)) try out.append(allocator, p);
        }
        return out.toOwnedSlice(allocator);
    }
};

pub fn load(allocator: std.mem.Allocator, io: std.Io) !Catalog {
    const data = std.Io.Dir.cwd().readFileAlloc(io, "config/packages.toml", allocator, .limited(256 * 1024)) catch |err| switch (err) {
        error.FileNotFound => return .{ .packages = &.{} },
        else => return err,
    };
    defer allocator.free(data);
    return parse(allocator, data);
}

fn parseInlineArray(allocator: std.mem.Allocator, s: []const u8) ![][]const u8 {
    const trimmed = std.mem.trim(u8, s, " \t");
    if (trimmed.len < 2 or trimmed[0] != '[' or trimmed[trimmed.len - 1] != ']')
        return allocator.dupe([]const u8, &.{});

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

const PkgBuilder = struct {
    id: ?[]const u8 = null,
    description: ?[]const u8 = null,
    profiles: ?[][]const u8 = null,
    platforms: ?[][]const u8 = null,
    config_paths: ?[][]const u8 = null,
    pacman: ?[]const u8 = null,
    aur: ?[]const u8 = null,
    brew: ?[]const u8 = null,
    brew_cask: ?[]const u8 = null,
    check_cmd: ?[]const u8 = null,
    skip: ?[]const u8 = null,
    install_script: ?[]const u8 = null,
    service_user: ?[]const u8 = null,
    service_system: ?[]const u8 = null,
    groups: ?[][]const u8 = null,
    post_cmd: ?[]const u8 = null,
    font_pkg: bool = false,

    fn commit(self: *PkgBuilder, allocator: std.mem.Allocator, list: *std.ArrayList(Package)) !void {
        const id = self.id orelse return;
        try list.append(allocator, .{
            .id = id,
            .description = self.description orelse try allocator.dupe(u8, ""),
            .profiles = self.profiles orelse try allocator.dupe([]const u8, &.{}),
            .platforms = self.platforms orelse try allocator.dupe([]const u8, &.{}),
            .config_paths = self.config_paths orelse try allocator.dupe([]const u8, &.{}),
            .pacman = self.pacman,
            .aur = self.aur,
            .brew = self.brew,
            .brew_cask = self.brew_cask,
            .check_cmd = self.check_cmd,
            .skip = self.skip,
            .install_script = self.install_script,
            .service_user = self.service_user,
            .service_system = self.service_system,
            .groups = self.groups orelse try allocator.dupe([]const u8, &.{}),
            .post_cmd = self.post_cmd,
            .font_pkg = self.font_pkg,
        });
        self.* = .{};
    }

    fn freePartial(self: PkgBuilder, allocator: std.mem.Allocator) void {
        if (self.id) |s| allocator.free(s);
        if (self.description) |s| allocator.free(s);
        if (self.profiles) |arr| { for (arr) |p| allocator.free(p); allocator.free(arr); }
        if (self.platforms) |arr| { for (arr) |p| allocator.free(p); allocator.free(arr); }
        if (self.config_paths) |arr| { for (arr) |p| allocator.free(p); allocator.free(arr); }
        if (self.pacman) |s| allocator.free(s);
        if (self.aur) |s| allocator.free(s);
        if (self.brew) |s| allocator.free(s);
        if (self.brew_cask) |s| allocator.free(s);
        if (self.check_cmd) |s| allocator.free(s);
        if (self.skip) |s| allocator.free(s);
        if (self.install_script) |s| allocator.free(s);
        if (self.service_user) |s| allocator.free(s);
        if (self.service_system) |s| allocator.free(s);
        if (self.groups) |arr| { for (arr) |g| allocator.free(g); allocator.free(arr); }
        if (self.post_cmd) |s| allocator.free(s);
    }
};

fn parse(allocator: std.mem.Allocator, data: []const u8) !Catalog {
    var list = std.ArrayList(Package).empty;
    errdefer {
        for (list.items) |p| p.deinit(allocator);
        list.deinit(allocator);
    }

    var cur = PkgBuilder{};
    var in_package = false;
    defer cur.freePartial(allocator);

    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        const trimmed = std.mem.trim(u8, line, " \t\r\n");
        if (trimmed.len == 0 or trimmed[0] == '#') continue;

        if (std.mem.eql(u8, trimmed, "[[package]]")) {
            if (in_package) try cur.commit(allocator, &list);
            cur = .{};
            in_package = true;
            continue;
        }
        if (trimmed[0] == '[') continue; // ignore other sections

        if (!in_package) continue;

        const eq = std.mem.indexOfScalar(u8, trimmed, '=') orelse continue;
        const key = std.mem.trim(u8, trimmed[0..eq], " \t");
        const raw_val = std.mem.trim(u8, trimmed[eq + 1 ..], " \t");
        const val = unquote(raw_val);

        if (std.mem.eql(u8, key, "id")) {
            if (cur.id) |s| allocator.free(s);
            cur.id = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "description")) {
            if (cur.description) |s| allocator.free(s);
            cur.description = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "profiles")) {
            if (cur.profiles) |arr| { for (arr) |p| allocator.free(p); allocator.free(arr); }
            cur.profiles = try parseInlineArray(allocator, raw_val);
        } else if (std.mem.eql(u8, key, "platforms")) {
            if (cur.platforms) |arr| { for (arr) |p| allocator.free(p); allocator.free(arr); }
            cur.platforms = try parseInlineArray(allocator, raw_val);
        } else if (std.mem.eql(u8, key, "config_paths")) {
            if (cur.config_paths) |arr| { for (arr) |p| allocator.free(p); allocator.free(arr); }
            cur.config_paths = try parseInlineArray(allocator, raw_val);
        } else if (std.mem.eql(u8, key, "pacman")) {
            if (cur.pacman) |s| allocator.free(s);
            cur.pacman = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "aur")) {
            if (cur.aur) |s| allocator.free(s);
            cur.aur = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "brew")) {
            if (cur.brew) |s| allocator.free(s);
            cur.brew = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "brew_cask")) {
            if (cur.brew_cask) |s| allocator.free(s);
            cur.brew_cask = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "check_cmd")) {
            if (cur.check_cmd) |s| allocator.free(s);
            cur.check_cmd = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "skip")) {
            if (cur.skip) |s| allocator.free(s);
            cur.skip = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "install_script")) {
            if (cur.install_script) |s| allocator.free(s);
            cur.install_script = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "service_user")) {
            if (cur.service_user) |s| allocator.free(s);
            cur.service_user = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "service_system")) {
            if (cur.service_system) |s| allocator.free(s);
            cur.service_system = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "groups")) {
            if (cur.groups) |arr| { for (arr) |g| allocator.free(g); allocator.free(arr); }
            cur.groups = try parseInlineArray(allocator, raw_val);
        } else if (std.mem.eql(u8, key, "post_cmd")) {
            if (cur.post_cmd) |s| allocator.free(s);
            cur.post_cmd = try allocator.dupe(u8, val);
        } else if (std.mem.eql(u8, key, "font_pkg")) {
            cur.font_pkg = std.mem.eql(u8, val, "true");
        }
    }

    if (in_package) try cur.commit(allocator, &list);

    return .{ .packages = try list.toOwnedSlice(allocator) };
}

test "parse packages catalog" {
    const data =
        \\[[package]]
        \\id = "neovim"
        \\description = "Hyperextensible text editor"
        \\profiles = ["base"]
        \\platforms = ["linux", "macos"]
        \\config_paths = ["~/.config/nvim"]
        \\pacman = "neovim"
        \\brew = "neovim"
        \\check_cmd = "nvim"
        \\
        \\[[package]]
        \\id = "hyprland"
        \\description = "Wayland compositor"
        \\profiles = ["hyprland"]
        \\platforms = ["linux"]
        \\config_paths = ["~/.config/hypr"]
        \\pacman = "hyprland"
    ;
    var catalog = try parse(std.testing.allocator, data);
    defer catalog.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), catalog.packages.len);
    try std.testing.expectEqualStrings("neovim", catalog.packages[0].id);
    try std.testing.expectEqualStrings("nvim", catalog.packages[0].binaryCmd());
    try std.testing.expectEqualStrings("hyprland", catalog.packages[1].id);
    try std.testing.expect(catalog.packages[1].hasProfile("hyprland"));
    try std.testing.expect(!catalog.packages[1].hasPlatform("macos"));
}
