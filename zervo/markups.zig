pub const html = @import("markups/html.zig");
pub const imr = @import("markups/imr.zig");
pub const gemini = @import("markups/gemini.zig");

const std       = @import("std");
const Allocator = std.mem.Allocator;

pub fn from_mime(allocator: *Allocator, root: @import("url.zig").Url, mimeRaw: []const u8, text: []const u8) !?imr.Document {
    var mime = try @import("mime.zig").MimeType.parse(allocator, mimeRaw);
    defer mime.deinit();

    if (std.mem.eql(u8, mime.type, "text")) {
        if (std.mem.eql(u8, mime.subtype, "gemini")) {
            return try gemini.parse(allocator, root, text);
        } else if (std.mem.eql(u8, mime.subtype, "html")) {
            return try html.parse_imr(allocator, text);
        } else {
            return null;
        }
    } else {
        return null;
    }
}
