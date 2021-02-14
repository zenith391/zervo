//! Intermediate Markup Representation
//! This is used as an intermediate representation between markup languages (HTML, Gemini, etc.)
//! and the renderer. It is created by converting markup languages's document format.
//! IMR is DOM-based but does not have any textual representation.

const std = @import("std");
const Url = @import("../url.zig").Url;
pub const TagList = std.ArrayList(Tag);
const Real = f32;

pub const TagType = enum {
    container,
    text
};

pub const Color = packed struct {
    red: u8,
    green: u8,
    blue: u8,
    alpha: u8 = 255
};

pub const SizeUnit = union(enum) {
    /// Percent where 1 is 100%
    Percent: Real,
    Pixels: Real,
    ViewportWidth: Real,
    ViewportHeight: Real,
    Automatic: void,

    pub fn get(self: *SizeUnit, vw: Real, vh: Real) ?Real {
        return switch (self) {
            .Pixels => |pixels| pixels,
            .Percent => |percent| unreachable, // TODO
            .ViewportWidth => |vW| vw*vW,
            .ViewportHeight => |vH| vh*vH,
            .Automatic => null
        };
    }
};

pub const TextSize = union(enum) {
    Units: Real,
    Percent: Real,
};

pub const Style = struct {
    textColor: ?Color = null,
    width: SizeUnit = .Automatic,
    height: SizeUnit = .Automatic,
    lineHeight: Real = 1.2,
    fontFace: [:0]const u8 = "Nunito",
    fontSize: Real = 16,
};

pub const Tag = struct {
    parent: ?*Tag = null,
    allocator: ?*std.mem.Allocator,
    style: Style = .{},
    href: ?Url = null,
    id: ?[]const u8 = null,
    elementType: []const u8,
    layoutX: f64 = 0,
    layoutY: f64 = 0,
    data: union(TagType) {
        text: [:0]const u8,
        /// List of childrens tags
        container: TagList
    },

    pub fn getElementById(self: *const Tag, id: []const u8) ?*Tag {
        switch (self.data) {
            .container => |container| {
                for (container.items) |*tag| {
                    if (std.mem.eql(u8, tag.id, id)) return tag;
                    if (tag.getElementById(id)) |elem| {
                        return elem;
                    }
                }
            },
            else => {}
        }
    }

    pub fn deinit(self: *const Tag) void {
        if (self.href) |href| href.deinit();
        switch (self.data) {
            .text => |text| {
                if (self.allocator) |allocator| allocator.free(text);
            },
            .container => |*tags| {
                for (tags.items) |*tag| {
                    tag.deinit();
                }
                tags.deinit();
            }
        }
    }
};

pub const Document = struct {
    tags: TagList,

    pub fn getElementById(self: *const Document, id: []const u8) ?*Tag {
        for (self.tags.items) |*tag| {
            if (std.mem.eql(u8, tag.id, id)) return tag;
            if (tag.getElementById(id)) |elem| {
                return elem;
            }
        }
    }

    pub fn deinit(self: *const Document) void {
        for (self.tags.items) |*tag| {
            tag.deinit();
        }
        self.tags.deinit();
    }
};
