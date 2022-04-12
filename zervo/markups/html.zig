//! HyperText Markup Language
//! This parses HTML documents from text into a DOM.
//! HTML documents can be converted to IMR using the `to_imr` function.
//! Alternatively, HTML text can be directly parsed to IMR using the `parse_imr` function.

const std = @import("std");
const imr = @import("imr.zig");
const Allocator = std.mem.Allocator;
const eqlIgnoreCase = std.ascii.eqlIgnoreCase;

pub const TagList = std.ArrayList(Tag);
pub const AttributeMap = std.StringHashMap([]const u8);

pub const Tag = struct {
    name: []const u8,
    text: ?[:0]const u8,
    childrens: TagList,
    attributes: AttributeMap,
    parent: ?*Tag,

    pub fn deinit(self: *Tag) void {
        if (!std.mem.eql(u8, self.name, "#text")) {
            for (self.childrens.items) |*child| {
                child.deinit();
            }
            self.childrens.deinit();
        } else {
            // TODO: free text and the tag itself
        }
    }
};

pub const Document = struct {
    tags: TagList,

    pub fn deinit(self: *Document) void {
        for (self.tags.items) |*tag| {
            tag.deinit();
        }
        self.tags.deinit();
    }
};

const voidElements = [_][]const u8 {
    "area", "base", "br", "col", "embed",
    "hr", "img", "input", "link", "meta",
    "param", "source", "track", "wbr"
};

fn to_imr_tag(allocator: Allocator, tag: Tag, parent: ?*imr.Tag) anyerror!imr.Tag {
    if (tag.text) |text| {
        std.log.info("parsed text {s}", .{text});
        return imr.Tag {
            .allocator = allocator,
            .elementType = "#text",
            .parent = parent,
            .data = .{
                .text = text
            }
        };
    } else {
        var self = imr.Tag {
            .allocator = allocator,
            .elementType = tag.name,
            .parent = parent,
            .data = .{
                .container = imr.TagList.init(allocator)
            }
        };
        for (tag.childrens.items) |child| {
            try self.data.container.append(try to_imr_tag(allocator, child, &self));
        }
        return self;
    }
}

/// Convert an HTML document to an IMR document.
/// Memory is caller owned. The HTML document is left untouched and is not freed.
pub fn to_imr(allocator: Allocator, document: Document) !imr.Document {
    var result: imr.Document = .{
        .tags = imr.TagList.init(allocator)
    };

    for (document.tags.items) |child| {
        try result.tags.append(try to_imr_tag(allocator, child, null));
    }

    return result;
}

/// Parses `text` into an IMR document.
/// Note that this method returns tags that depend on slices created from text.
/// This means you cannot free text unless done with document.
/// Memory is caller owned.
pub fn parse_imr(allocator: Allocator, text: []const u8) !imr.Document {
    var html = try parse(allocator, text);
    const doc = try to_imr(allocator, html);
    html.deinit();
    return doc;
}

/// Parses `text` into an HTML document.
/// Note that this method returns tags that depend on slices created from text.
/// This means you cannot free text unless done with document.
/// Memory is caller owned.
pub fn parse(allocator: Allocator, text: []const u8) !Document {
    var i: usize = 0;

    var startTag: bool = false;
    var endTag: bool = false;

    var inComment: bool = false;

    var rootChildrens: TagList = TagList.init(allocator);
    var currentTag: ?*Tag = null;

    var parseAttrName: bool = false;
    var parseAttrValue: bool = false;

    var tagNameStart: usize = 0;
    var tagNameEnd: usize = 0;

    var attrNameStart: usize = 0;
    var attrNameEnd: usize = 0;
    var attrValueStart: usize = 0;

    var textStart: usize = 0;

    while (i < text.len) {
        const ch = text[i];
        if (inComment) {
            const behind = text[(i-3)..i];
            if (std.mem.eql(u8, behind, "-->")) {
                inComment = false;
            }
        } else if (i > 3) {
            const behind = text[(i-4)..i];
            if (std.mem.eql(u8, behind, "<!--")) {
                startTag = false;
                inComment = true;
            }
        }
        if (!startTag and !endTag) {
            if (ch == '<') {
                if (textStart != 0) {
                    var tag = try allocator.create(Tag);
                    tag.name = "#text";
                    tag.text = try allocator.dupeZ(u8, text[textStart..i]);
                    std.debug.print("text: {s} current tag is null ? {}\n", .{tag.text.?, currentTag == null});
                    tag.parent = currentTag;
                    textStart = 0;
                    if (currentTag != null) try currentTag.?.childrens.append(tag.*);
                }
                startTag = true;
                tagNameStart = i+1;
                tagNameEnd = 0;
            }
        } else {
            if (parseAttrName and ch == '=') {
                parseAttrName = false;
                parseAttrValue = true;
                attrNameEnd = i;
                attrValueStart = i+1;
            }

            if (std.ascii.isSpace(ch)) {
                if (tagNameEnd == 0) tagNameEnd = i;
                if (parseAttrName and currentTag != null) {
                    try currentTag.?.attributes.put(text[attrNameStart..i], "");
                }
                parseAttrName = true;
                attrNameStart = i+1;
            }

            if (i > 0 and ch == '/' and text[i-1] == '<') {
                startTag = false;
                endTag = true;
                tagNameStart = i+1;
                tagNameEnd = 0;
            }

            if (ch == '>') {
                if (tagNameEnd == 0) {
                    tagNameEnd = i;
                }
                parseAttrName = false;
                parseAttrValue = false;
                textStart = i+1;

                const tagName = text[tagNameStart..tagNameEnd];
                std.debug.print("tag name: {s}, {}\n", .{tagName, startTag});
                if (startTag) {
                    startTag = false;
                    if (eqlIgnoreCase(tagName, "!DOCTYPE")) {
                        continue;
                    }
                    var oldTag = currentTag;
                    var tag = try allocator.create(Tag);
                    tag.name = tagName;
                    tag.childrens = TagList.init(allocator);
                    tag.attributes = AttributeMap.init(allocator);
                    tag.parent = oldTag;

                    for (voidElements) |elem| {
                        if (eqlIgnoreCase(tagName, elem)) {
                            endTag = true; // also an end tag
                        }
                    }

                    currentTag = tag;
                }
                if (endTag) {
                    endTag = false;
                    var parent = currentTag.?.parent;
                    if (parent != null) {
                        try parent.?.childrens.append(currentTag.?.*);
                    } else {
                        try rootChildrens.append(currentTag.?.*);
                    }
                    currentTag = parent;
                }
            }
        }
        i += 1;
    }

    return Document {
        .tags = rootChildrens
    };
}
