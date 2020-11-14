const std = @import("std");


pub const Uri = struct {
    scheme: []const u8,
    host: []const u8,
    path: []const u8,
    port: ?u16,

    pub fn format(self: *const Uri, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) std.os.WriteError!void {
        try writer.print("{}://{}", .{self.scheme, self.host});
        if (self.port) |port| {
            try writer.print(":{}", .{port});
        }
        try writer.writeAll(self.path);
    }
};
