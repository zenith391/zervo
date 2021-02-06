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

/// Parses `text` into an IMR document.
/// Note that this method returns tags that depend on slices created from text.
/// This means you cannot free text unless done with document.
/// Memory is caller owned.
pub fn parse(allocator: *Allocator, root: Url, text: []const u8) !imr.Document {
    var pos: usize = 0;
    var lineStart: usize = 0;
    var lineType: LineType = .text;

    var rootChildrens: imr.TagList = imr.TagList.init(allocator);
    errdefer rootChildrens.deinit();
    var instart: bool = true;
    var headingSize: u8 = 0;
    var preformatting: bool = false;

    while (pos < text.len) {
        const ch = text[pos];
        if (ch == '\n') {
            if (!preformatting) {
                while ((text[lineStart] == ' ' or text[lineStart] == '\t') and lineStart < pos) {
                    lineStart += 1;
                }
            }
            const line = text[lineStart..pos];
            //std.debug.warn("line: {}, type: {}\n", .{line, lineType});

            switch (lineType) {
                .text => {
                    var tag = imr.Tag {
                        .parent = null,
                        .allocator = allocator,
                        .data = .{
                            .text = try allocator.dupeZ(u8, line)
                        }
                    };
                    if (preformatting) {
                        tag.style.fontFace = "monospace";
                        tag.style.fontSize = 10;
                    }
                    try rootChildrens.append(tag);
                },
                .heading => {
                    const tag = imr.Tag {
                        .parent = null,
                        .allocator = allocator,
                        .style = .{
                            .fontSize = 42.0 * (1 - @log10(@intToFloat(f32, headingSize+1))),
                            .lineHeight = 1.0
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
                    const url = line[0..urlEnd];
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
                    const tag = imr.Tag {
                        .parent = null,
                        .allocator = allocator,
                        .href = href,
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
        } else if (ch == '#' and instart and !preformatting) {
            headingSize += 1;
            lineType = .heading;
            lineStart = pos+1;
        } else {
            instart = false;
        }
        if (pos < text.len-3 and pos <= lineStart and std.mem.eql(u8, text[pos..(pos+2)], "=>") and !preformatting) {
            lineType = .link;
            lineStart = pos+2;
            pos += 1;
        } else if (pos < text.len-4 and pos <= lineStart and std.mem.eql(u8, text[pos..(pos+3)], "```")) {
            preformatting = !preformatting;
            if (std.mem.indexOfScalarPos(u8, text, pos, '\n')) |nextLine| {
                lineStart = nextLine;
                pos = nextLine-1;
            }
        }
        pos += 1;
    }

    return imr.Document {
        .tags = rootChildrens
    };
}
