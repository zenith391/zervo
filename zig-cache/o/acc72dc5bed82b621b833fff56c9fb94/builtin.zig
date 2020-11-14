usingnamespace @import("std").builtin;
/// Deprecated
pub const arch = Target.current.cpu.arch;
/// Deprecated
pub const endian = Target.current.cpu.arch.endian();
pub const output_mode = OutputMode.Exe;
pub const link_mode = LinkMode.Static;
pub const is_test = false;
pub const single_threaded = false;
pub const abi = Abi.gnu;
pub const cpu: Cpu = Cpu{
    .arch = .x86_64,
    .model = &Target.x86.cpu.bdver3,
    .features = Target.x86.featureSet(&[_]Target.x86.Feature{
        .@"64bit",
        .@"aes",
        .@"avx",
        .@"bmi",
        .@"branchfusion",
        .@"cmov",
        .@"cx16",
        .@"cx8",
        .@"f16c",
        .@"fast_11bytenop",
        .@"fast_bextr",
        .@"fast_scalar_shift_masks",
        .@"fma",
        .@"fma4",
        .@"fsgsbase",
        .@"fxsr",
        .@"lwp",
        .@"lzcnt",
        .@"mmx",
        .@"nopl",
        .@"pclmul",
        .@"popcnt",
        .@"prfchw",
        .@"sahf",
        .@"slow_shld",
        .@"sse",
        .@"sse2",
        .@"sse3",
        .@"sse4_1",
        .@"sse4_2",
        .@"sse4a",
        .@"ssse3",
        .@"tbm",
        .@"vzeroupper",
        .@"x87",
        .@"xop",
        .@"xsave",
        .@"xsaveopt",
    }),
};
pub const os = Os{
    .tag = .linux,
    .version_range = .{ .linux = .{
        .range = .{
            .min = .{
                .major = 5,
                .minor = 4,
                .patch = 0,
            },
            .max = .{
                .major = 5,
                .minor = 4,
                .patch = 0,
            },
        },
        .glibc = .{
            .major = 2,
            .minor = 17,
            .patch = 0,
        },
    }},
};
pub const object_format = ObjectFormat.elf;
pub const mode = Mode.Debug;
pub const link_libc = false;
pub const link_libcpp = false;
pub const have_error_return_tracing = true;
pub const valgrind_support = true;
pub const position_independent_code = false;
pub const strip_debug_info = false;
pub const code_model = CodeModel.default;
