const std = @import("std");
const Allocator = std.mem.Allocator;

pub const MimeType = struct {
    allocator: ?*Allocator = null,
    type: []const u8,
    subtype: []const u8,
    parameters: std.StringHashMap([]const u8),

    pub fn parse(allocator: *Allocator, text: []const u8) !MimeType {
        if (std.mem.indexOfScalar(u8, text, '/')) |separator| {
            const mimeType = try std.ascii.allocLowerString(allocator, text[0..separator]);
            const firstParam = std.mem.indexOfScalar(u8, text, ';') orelse text.len;
            const subtype = try std.ascii.allocLowerString(allocator, text[separator+1..firstParam]);
            var parameters = std.StringHashMap([]const u8).init(allocator);

            return MimeType {
                .allocator = allocator,
                .type = mimeType,
                .subtype = subtype,
                .parameters = parameters
            };
        } else {
            return error.InvalidMime;
        }
    }

    pub fn deinit(self: *MimeType) void {
        if (self.allocator) |alloc| {
            alloc.free(self.type);
            alloc.free(self.subtype);
        }
        self.parameters.deinit();
    }

    pub fn getCharset(self: *MimeType) []const u8 {
        return self.parameters.get("charset") orelse "utf-8";
    }

    pub fn format(self: *const MimeType, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        try writer.print("{s}/{s}", .{self.type, self.subtype});
    }
};
