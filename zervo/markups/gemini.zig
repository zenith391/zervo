//! Gemini Markup
//! This parses Gemini documents into IMR.

const std = @import("std");
const imr = @import("imr.zig");
const Allocator = std.mem.Allocator;
const eqlIgnoreCase = std.ascii.eqlIgnoreCase;
usingnamespace @import("../url.zig");

const LineType = enum {
    text,
    link,
    heading
};

const ParserState = union(enum) {
    Text,
    Link,
    Preformatting,
    /// usize = heading level
    Heading: usize
};

inline fn getLineEnd(text: []const u8, pos: usize) usize {
    const newPos = std.mem.indexOfScalarPos(u8, text, pos, '\r') orelse (std.mem.indexOfScalarPos(u8, text, pos, '\n') orelse text.len);
    if (newPos == text.len or text[newPos] == '\r') {
        return newPos;
    } else if (text[newPos] == '\n') {
        return if (newPos >= 1 and text[newPos-1] == '\r') newPos-1 else newPos;
    } else {
        unreachable;
    }
}

inline fn getNextLine(text: []const u8, pos: usize) usize {
    const newPos = std.mem.indexOfScalarPos(u8, text, pos, '\r') orelse (std.mem.indexOfScalarPos(u8, text, pos, '\n') orelse text.len);
    if (newPos == text.len) {
        return newPos;
    } else if (text[newPos] == '\n') {
        return newPos+1;
    } else if (text[newPos] == '\r') {
        return newPos+2;
    } else {
        unreachable;
    }
}

/// Parses `text` into an IMR document.
/// Note that this method returns tags that depend on slices created from text.
/// This means you cannot free text unless done with document.
/// Memory is caller owned.
pub fn parse(allocator: *Allocator, root: Url, text: []const u8) !imr.Document {
    var rootChildrens: imr.TagList = imr.TagList.init(allocator);
    errdefer rootChildrens.deinit();

    var pos: usize = 0;
    var state = ParserState { .Text = {} };

    while (pos < text.len) {
        switch (state) {
            .Text => {
                if (pos < text.len-3 and std.mem.eql(u8, text[pos..pos+2], "=>")) {
                    pos += 2;
                    state = .Link;
                } else if (pos < text.len-4 and std.mem.eql(u8, text[pos..pos+3], "```")) {
                    pos = getNextLine(text, pos);
                    state = .Preformatting;
                } else if (pos < text.len-2 and text[pos] == '#') {
                    state = .{ .Heading = 0 };
                } else {
                    const end = getLineEnd(text, pos);
                    const tag = imr.Tag {
                        .allocator = allocator,
                        .elementType = "text",
                        .data = .{
                            .text = try allocator.dupeZ(u8, text[pos..end])
                        }
                    };
                    try rootChildrens.append(tag);
                    pos = getNextLine(text, pos);
                }
            },
            .Link => {
                const end = getLineEnd(text, pos);
                while (text[pos] == ' ' or text[pos] == '\t') { pos += 1; }
                var urlEnd: usize = pos;
                while (text[urlEnd] != ' ' and text[urlEnd] != '\t' and text[urlEnd] != '\r' and text[urlEnd] != '\n') { urlEnd += 1; }

                var nameStart: usize = urlEnd;
                while ((text[nameStart] == ' ' or text[nameStart] == '\t') and nameStart < text.len-1) { nameStart += 1; }
                const url = text[pos..urlEnd];
                const href = root.combine(allocator, url) catch |err| blk: {
                    switch (err) {
                        UrlError.TooLong => {
                            std.log.warn("URL too long: {}", .{url});
                            break :blk root.dupe(allocator) catch |e| return e;
                        },
                        UrlError.EmptyString => {
                            break :blk root.dupe(allocator) catch |e| return e;
                        },
                        else => return err
                    }
                };

                const name = if (urlEnd == end) text[pos..end] else text[nameStart..end];
                const tag = imr.Tag {
                    .allocator = allocator,
                    .href = href,
                    .elementType = "link",
                    .style = .{
                        .textColor = .{.red = 0x00, .green = 0x00, .blue = 0xFF}
                    },
                    .data = .{
                        .text = try allocator.dupeZ(u8, name)
                    }
                };
                try rootChildrens.append(tag);
                pos = getNextLine(text, pos);
                state = .Text;
            },
            .Heading => |level| {
                if (text[pos] == '#') {
                    pos += 1;
                    state = .{ .Heading = level+1 };
                } else {
                    const end = getLineEnd(text, pos);
                    while (text[pos] == ' ' or text[pos] == '\t') { pos += 1; }

                    var buf: [2]u8 = undefined;

                    const tag = imr.Tag {
                        .allocator = allocator,
                        .elementType = "h",
                        .style = .{
                            .fontSize = 42.0 * (1 - @log10(@intToFloat(f32, level+1))),
                            .lineHeight = 1.0
                        },
                        .data = .{
                            .text = try allocator.dupeZ(u8, text[pos..end])
                        }
                    };
                    try rootChildrens.append(tag);
                    pos = getNextLine(text, pos);
                    state = .Text;
                }
            },
            .Preformatting => {
                const end = std.mem.indexOfPos(u8, text, pos, "```") orelse text.len;
                const tag = imr.Tag {
                    .allocator = allocator,
                    .elementType = "pre",
                    .style = .{
                        .fontFace = "monospace",
                        .fontSize = 10
                    },
                    .data = .{
                        .text = try allocator.dupeZ(u8, text[pos..end])
                    }
                };
                try rootChildrens.append(tag);
                pos = getNextLine(text, end);
                state = .Text;
            }
        }
    }

    return imr.Document {
        .tags = rootChildrens
    };
}
