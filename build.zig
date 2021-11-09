const std = @import("std");
const deps = @import("deps.zig");
const Builder = std.build.Builder;
const Tag = std.Target.Os.Tag;
const Pkg = std.build.Pkg;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("demo", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    const ssl = Pkg {
        .name = "ssl",
        .path = std.build.FileSource.relative("openssl/ssl.zig")
    };

    const zervo = Pkg {
        .name = "zervo",
        .path = std.build.FileSource.relative("zervo/zervo.zig"),
        .dependencies = &([_]Pkg {ssl})
    };
    
    exe.addPackage(ssl);
    _ = zervo;
    exe.addPackage(zervo);
    deps.addAllTo(exe);

    // cairo module
    //exe.addIncludeDir("./cairo/src");
    // exe.linkSystemLibrary("cairo");
    // exe.linkSystemLibrary("pango");
    // exe.linkSystemLibrary("pangocairo");
    // exe.linkSystemLibrary("GL");
    // exe.linkSystemLibrary("glfw");
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
