const std = @import("std");
const Pkg = std.build.Pkg;
const string = []const u8;

pub const cache = ".zigmod/deps";

pub fn addAllTo(exe: *std.build.LibExeObjStep) void {
    @setEvalBranchQuota(1_000_000);
    for (packages) |pkg| {
        exe.addPackage(pkg.pkg.?);
    }
    inline for (std.meta.declarations(package_data)) |decl| {
        const pkg = @as(Package, @field(package_data, decl.name));
        var llc = false;
        inline for (pkg.system_libs) |item| {
            exe.linkSystemLibrary(item);
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
        if (llc) {
            exe.linkLibC();
        }
    }
}

pub const Package = struct {
    directory: string,
    pkg: ?Pkg = null,
    c_include_dirs: []const string = &.{},
    c_source_files: []const string = &.{},
    c_source_flags: []const string = &.{},
    system_libs: []const string = &.{},
};

const dirs = struct {
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
        .system_libs = &.{ "crypto", "ssl", "c", },
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
    pub const zervobrowser = @import(".zigmod/deps/../../src/main.zig");
    pub const zgt = @import(".zigmod/deps/git/github.com/zenith391/zgt/src/main.zig");
};
