//! Intermediate Markup Representation
//! This is used as an intermediate representation between markup languages (HTML, Gemini, etc.)
//! and the renderer. It is created by converting markup languages's document format.
//! IMR is DOM-based but does not have any textual representation.

const std = @import("std");
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
    /// From 0 to 1
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

pub const Style = struct {
    textColor: ?Color = null,
    width: SizeUnit = .Automatic,
    height: SizeUnit = .Automatic,
    lineHeight: Real = 1.6,
    fontSize: Real = 16,
};

pub const Tag = struct {
    parent: ?*Tag,
    allocator: ?*std.mem.Allocator,
    style: Style = .{},
    data: union(TagType) {
        text: [:0]const u8,
        /// List of childrens tags
        container: TagList
    },

    pub fn deinit(self: *const Tag) void {
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

    pub fn deinit(self: *const Document) void {
        for (self.tags.items) |*tag| {
            tag.deinit();
        }
        self.tags.deinit();
    }
};
