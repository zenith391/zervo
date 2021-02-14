pub const std = @import("std");
pub const imr = @import("markups/imr.zig");
const Url = @import("url.zig").Url;
const Document = imr.Document;
const Tag = imr.Tag;
const Allocator = std.mem.Allocator;

const Event = union(enum) {
    MouseButton: struct {
        pressed: bool,
        x: f64,
        y: f64
    }
};

pub fn RenderContext(comptime T: type) type {
    return struct {
        /// Instance of type T.
        graphics: *T,
        document: Document,
        width: f64 = 0,
        height: f64 = 0,
        offsetY: f64 = 0,
        /// Used for smooth scrolling
        offsetYTarget: f64 = 0,
        // Component position to use if drawing on the same surface as the render context
        x: f64 = 0,
        y: f64 = 0,

        linkCallback: ?fn(ctx: *Self, url: Url) anyerror!void = null,
        const Self = @This();

        pub fn setup(self: *const Self) void {
            self.graphics.mouseButtonCb = Self.mouseButtonCallback;
            self.graphics.mouseScrollCb = Self.mouseScrollCallback;
            self.graphics.userData = @ptrToInt(self);
        }

        pub fn layout(self: *Self) void {
            var y: f64 = 0;
            for (self.document.tags.items) |*tag| {
                self.layoutTag(tag, &y);
            }
        }

        fn layoutTag(self: *Self, tag: *Tag, y: *f64) void {
            const style = tag.style;
            const g = self.graphics;
            switch (tag.data) {
                .text => |text| {
                    g.setFontFace(style.fontFace);
                    g.setFontSize(style.fontSize);
                    g.setTextWrap(g.getWidth());
                    const metrics = g.getTextMetrics(text);
                    tag.layoutY = y.*;
                    y.* += metrics.height;
                },
                .container => |childrens| {
                    for (childrens.items) |*child| {
                        self.layoutTag(child, y);
                    }
                }
            }
        }

        fn setColor(self: *const Self, color: imr.Color) void {
            const red = @intToFloat(f64, color.red) / 255.0;
            const green = @intToFloat(f64, color.green) / 255.0;
            const blue = @intToFloat(f64, color.blue) / 255.0;
            self.graphics.setSourceRGB(red, green, blue);
        }

        fn lerp(a: f64, b: f64, t: f64) f64 {
            return a * (1-t) + b * t;
        }

        pub fn render(self: *Self) void {
            self.width = self.graphics.getWidth();
            self.height = self.graphics.getHeight();
            if (!std.math.approxEqAbs(f64, self.offsetY, self.offsetYTarget, 0.01)) {
                self.offsetY = lerp(self.offsetY, self.offsetYTarget, 0.4);
                self.graphics.request_next_frame = true;
            }
            for (self.document.tags.items) |tag| {
                // if (std.event.Loop.instance) |loop| {
                //     loop.yield();
                // }
                if (self.renderTag(tag) catch unreachable) break;
            }
        }

        fn renderText(self: *const Self, tag: Tag, text: [:0]const u8, y: f64) void {
            const g = self.graphics;
            g.moveTo(0, y + self.offsetY + self.y);
            g.text(text);
            g.stroke();
        }

        fn renderTag(self: *const Self, tag: Tag) anyerror!bool {
            const style = tag.style;
            const g = self.graphics;
            switch (tag.data) {
                .text => |text| {
                    g.setFontFace(style.fontFace);
                    g.setFontSize(style.fontSize);
                    g.setTextWrap(self.width);
                    const metrics = g.getTextMetrics(text);
                    const y = tag.layoutY;
                    if (y > self.height-self.offsetY) {
                        return true;
                    }
                    if (y + metrics.height >= -self.offsetY) {
                        if (style.textColor) |color| {
                            self.setColor(color);
                        } else {
                            g.setSourceRGB(0, 0, 0);
                        }
                        self.renderText(tag, text, y);
                    }
                },
                .container => |childrens| {
                    for (childrens.items) |child| {
                        if (try self.renderTag(child)) return true;
                    }
                }
            }
            return false;
        }

        fn mouseScrollCallback(backend: *T, yOffset: f64) void {
            const self = @intToPtr(*Self, backend.userData);

            self.offsetYTarget += yOffset * 35.0;
            if (self.offsetYTarget > 0) self.offsetYTarget = 0;
            backend.frame_requested = true;
        }

        fn mouseButtonCallback(backend: *T, button: T.MouseButton, pressed: bool) void {
            const self = @intToPtr(*Self, backend.userData);
            const event = Event {
                .MouseButton = .{
                    .pressed = pressed,
                    .x = backend.getCursorX() - self.x,
                    .y = backend.getCursorY() - self.y - self.offsetY
                }
            };
            if (backend.getCursorX() < self.x or backend.getCursorY() < self.y) return;

            for (self.document.tags.items) |tag| {
                const stopLoop = self.processTag(tag, &event) catch |err| {
                    std.debug.warn("error: {}\n", .{err});
                    if (@errorReturnTrace()) |trace| {
                        std.debug.dumpStackTrace(trace.*);
                    }
                    return;
                };
                if (stopLoop) break;
            }
        }

        fn processTag(self: *Self, tag: Tag, event: *const Event) anyerror!bool {
            const style = tag.style;
            const g = self.graphics;
            switch (tag.data) {
                .text => |text| {
                    g.setFontSize(style.fontSize);
                    g.setTextWrap(self.width);
                    const metrics = g.getTextMetrics(text);
                    const y = tag.layoutY;

                    switch (event.*) {
                        .MouseButton => |evt| {
                            if (tag.href) |href| {
                                const cx = evt.x;
                                const cy = evt.y;
                                if (!evt.pressed and cx > 0 and cx <= 0 + metrics.width and cy > y and cy <= y + metrics.height) {
                                    if (self.linkCallback) |cb| {
                                        try cb(self, href);
                                        g.*.frame_requested = true;
                                        return true;
                                    }
                                }
                            }
                        }
                    }
                },
                .container => |childrens| {
                    for (childrens.items) |child| {
                        if (try self.processTag(child, event)) return true;
                    }
                }
            }
            return false;
        }
    };
}