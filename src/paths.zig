const std = @import("std");

/// Project paths relative to project_dir
pub const MANIFEST = "desperta.toml";
pub const CONFIG_DIR = "config";
pub const PACKAGES_CATALOG = "config/packages.toml";
pub const DENYLIST = "config/denylist.txt";
pub const TRACKED_PATHS = "config/tracked-paths.txt";
pub const DOTFILES_DIR = "dotfiles";
pub const DOTFILES_DEFAULT = "dotfiles/default";

/// Build a full path for a project file
pub fn projectPath(
    allocator: std.mem.Allocator,
    project_dir: []const u8,
    relative: []const u8,
) ![]const u8 {
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ project_dir, relative });
}
