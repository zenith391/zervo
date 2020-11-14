//! Gemini Markup
//! This parses Gemini documents into IMR.

const std = @import("std");
const imr = @import("imr.zig");
const Allocator = std.mem.Allocator;
const eqlIgnoreCase = std.ascii.eqlIgnoreCase;

const LineType = enum {
    text,
    link,
    heading
};

/// Parses `text` into an IMR document.
/// Note that this method returns tags that depend on slices created from text.
/// This means you cannot free text unless done with document.
/// Memory is caller owned.
pub fn parse(allocator: *Allocator, text: []const u8) !imr.Document {
    var pos: usize = 0;
    var lineStart: usize = 0;
    var lineType: LineType = .text;

    var rootChildrens: imr.TagList = imr.TagList.init(allocator);
    var instart: bool = true;
    var headingSize: u8 = 0;

    while (pos < text.len) {
        const ch = text[pos];
        if (ch == '\n') {
            while (text[lineStart] == ' ') lineStart += 1;
            const line = text[lineStart..pos];
            std.debug.warn("line: {}, type: {}\n", .{line, lineType});

            switch (lineType) {
                .text => {
                    const tag = imr.Tag {
                        .parent = null,
                        .allocator = allocator,
                        .data = .{
                            .text = try allocator.dupeZ(u8, line)
                        }
                    };
                    try rootChildrens.append(tag);
                },
                .heading => {
                    const tag = imr.Tag {
                        .parent = null,
                        .allocator = allocator,
                        .style = .{
                            .fontSize = 42.0 * (1 - @log10(@intToFloat(f32, headingSize+1))),
                            .lineHeight = 1.2
                        },
                        .data = .{
                            .text = try allocator.dupeZ(u8, line)
                        }
                    };
                    headingSize = 0;
                    try rootChildrens.append(tag);
                },
                .link => {
                    var space: usize = 0;
                    var urlEnd: usize = 0;
                    for (line) |c, i| {
                        space = i;
                        if (c != ' ' and c != '\t') {
                            if (urlEnd != 0) break;
                        } else {
                            urlEnd = i;
                        }
                    }
                    if (urlEnd == 0) {
                        urlEnd = line.len;
                        space = 0;
                    }
                    const tag = imr.Tag {
                        .parent = null,
                        .allocator = allocator,
                        .style = .{
                            .textColor = .{.red = 0x00, .green = 0x00, .blue = 0xFF}
                        },
                        .data = .{
                            .text = try allocator.dupeZ(u8, line[space..])
                        }
                    };
                    try rootChildrens.append(tag);
                }
            }

            lineStart = pos+1;
            lineType = .text;
            instart = true;
        } else if (ch == '#' and instart) {
            headingSize += 1;
            lineType = .heading;
            lineStart = pos+1;
        } else {
            instart = false;
        }
        if (pos < text.len-1 and std.mem.eql(u8, text[pos..(pos+2)], "=>")) {
            pos += 1;
            lineType = .link;
            lineStart = pos+2;
        }
        pos += 1;
    }

    return imr.Document {
        .tags = rootChildrens
    };
}
