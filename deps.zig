const std = @import("std");
const builtin = @import("builtin");
const Pkg = std.build.Pkg;
const string = []const u8;

pub const cache = ".zigmod/deps";

pub fn addAllTo(exe: *std.build.LibExeObjStep) void {
    checkMinZig(builtin.zig_version, exe);
    @setEvalBranchQuota(1_000_000);
    for (packages) |pkg| {
        exe.addPackage(pkg.pkg.?);
    }
    var llc = false;
    var vcpkg = false;
    inline for (comptime std.meta.declarations(package_data)) |decl| {
        const pkg = @as(Package, @field(package_data, decl.name));
        for (pkg.system_libs) |item| {
            exe.linkSystemLibrary(item);
            llc = true;
        }
        for (pkg.frameworks) |item| {
            if (!std.Target.current.isDarwin()) @panic(exe.builder.fmt("a dependency is attempting to link to the framework {s}, which is only possible under Darwin", .{item}));
            exe.linkFramework(item);
            llc = true;
        }
        inline for (pkg.c_include_dirs) |item| {
            exe.addIncludeDir(@field(dirs, decl.name) ++ "/" ++ item);
            llc = true;
        }
        inline for (pkg.c_source_files) |item| {
            exe.addCSourceFile(@field(dirs, decl.name) ++ "/" ++ item, pkg.c_source_flags);
            llc = true;
        }
        vcpkg = vcpkg or pkg.vcpkg;
    }
    if (llc) exe.linkLibC();
    if (builtin.os.tag == .windows and vcpkg) exe.addVcpkgPaths(.static) catch |err| @panic(@errorName(err));
}

pub const Package = struct {
    directory: string,
    pkg: ?Pkg = null,
    c_include_dirs: []const string = &.{},
    c_source_files: []const string = &.{},
    c_source_flags: []const string = &.{},
    system_libs: []const string = &.{},
    frameworks: []const string = &.{},
    vcpkg: bool = false,
};

fn checkMinZig(current: std.SemanticVersion, exe: *std.build.LibExeObjStep) void {
    const min = std.SemanticVersion.parse("null") catch return;
    if (current.order(min).compare(.lt)) @panic(exe.builder.fmt("Your Zig version v{} does not meet the minimum build requirement of v{}", .{current, min}));
}

pub const dirs = struct {
    pub const _root = "";
    pub const _q5z53vdb3fg2 = cache ++ "/../..";
    pub const _deeztnhr07fk = cache ++ "/git/github.com/zenith391/zgt";
};

pub const package_data = struct {
    pub const _q5z53vdb3fg2 = Package{
        .directory = dirs._q5z53vdb3fg2,
        .pkg = Pkg{ .name = "zervobrowser", .path = .{ .path = dirs._q5z53vdb3fg2 ++ "/src/main.zig" }, .dependencies = null },
    };
    pub const _deeztnhr07fk = Package{
        .directory = dirs._deeztnhr07fk,
        .pkg = Pkg{ .name = "zgt", .path = .{ .path = dirs._deeztnhr07fk ++ "/src/main.zig" }, .dependencies = null },
        .system_libs = &.{ "gtk+-3.0", "c" },
    };
    pub const _root = Package{
        .directory = dirs._root,
        .system_libs = &.{ "crypto", "ssl", "c", "crypto", "ssl", "c", },
    };
};

pub const packages = &[_]Package{
    package_data._q5z53vdb3fg2,
    package_data._deeztnhr07fk,
};

pub const pkgs = struct {
    pub const zervobrowser = package_data._q5z53vdb3fg2;
    pub const zgt = package_data._deeztnhr07fk;
};

pub const imports = struct {
    pub const zgt = @import(".zigmod/deps/git/github.com/zenith391/zgt/src/main.zig");
};
