const std = @import("std");
const Builder = std.build.Builder;
const Tag = std.Target.Os.Tag;
const Pkg = std.build.Pkg;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const os = target.getOsTag();
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("demo", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    const ssl = Pkg {
        .name = "ssl",
        .path = "openssl/ssl.zig"
    };

    const zervo = Pkg {
        .name = "zervo",
        .path = "zervo/zervo.zig",
        .dependencies = &([_]Pkg {ssl})
    };
    
    exe.addPackage(ssl);
    exe.addPackage(zervo);

    exe.linkSystemLibrary("crypto");
    exe.linkSystemLibrary("ssl");
    exe.linkSystemLibrary("c");

    // cairo module
    exe.addIncludeDir("./cairo/src");
    exe.linkSystemLibrary("cairo");
    exe.linkSystemLibrary("pango");
    exe.linkSystemLibrary("pangocairo");
    exe.linkSystemLibrary("GL");
    exe.linkSystemLibrary("glfw");
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
