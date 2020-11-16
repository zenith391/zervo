pub const std = @import("std");
pub const imr = @import("markups/imr.zig");
const Url = @import("url.zig").Url;
const Document = imr.Document;
const Tag = imr.Tag;

const Event = union(enum) {
    mouseButton: struct {
        pressed: bool
    }
};

pub fn RenderContext(comptime T: type) type {
    return struct {
        /// Instance of type T.
        graphics: *T,
        document: Document,

        linkCallback: ?fn(ctx: *Self, url: Url) anyerror!void = null,
        const Self = @This();

        pub fn setup(self: *const Self) void {
            self.graphics.mouseButtonCb = Self.mouseButtonCallback;
            self.graphics.userData = @ptrToInt(self);
        }

        pub fn render(self: *const Self) void {
            self.graphics.setSourceRGB(1, 1, 1);
            self.graphics.rectangle(0, 0, self.graphics.getWidth(), self.graphics.getHeight());
            self.graphics.fill();

            var y: f64 = 0;
            for (self.document.tags.items) |tag| {
                self.renderTag(tag, &y);
                if (std.event.Loop.instance) |loop| {
                    loop.yield();
                }
            }
            self.graphics.*.frame_requested = true;
        }

        fn setColor(self: *const Self, color: imr.Color) void {
            const red = @intToFloat(f64, color.red) / 255.0;
            const green = @intToFloat(f64, color.green) / 255.0;
            const blue = @intToFloat(f64, color.blue) / 255.0;
            self.graphics.setSourceRGB(red, green, blue);
        }

        fn renderTag(self: *const Self, tag: Tag, y: *f64) void {
            const style = tag.style;
            const g = self.graphics;
            switch (tag.data) {
                .text => |text| {
                    if (style.textColor) |color| {
                        self.setColor(color);
                    } else {
                        g.setSourceRGB(0, 0, 0);
                    }
                    g.setFontSize(style.fontSize);
                    const metrics = g.getTextMetrics(text);
                    g.moveTo(0, y.* + metrics.height);
                    g.text(text);
                    g.stroke();
                    y.* += (metrics.height) * style.lineHeight;
                },
                .container => |childrens| {
                    for (childrens.items) |child| {
                        self.renderTag(child, y);
                    }
                }
            }
        }

        fn mouseButtonCallback(backend: *T, button: T.MouseButton, pressed: bool) void {
            const event = Event {
                .mouseButton = .{
                    .pressed = pressed
                }
            };

            var self = @intToPtr(*Self, backend.userData);
            var y: f64 = 0;
            for (self.document.tags.items) |tag| {
                self.processTag(tag, &y, &event) catch |err| {
                    std.debug.warn("error: {}\n", .{err});
                    if (@errorReturnTrace()) |trace| {
                        std.debug.dumpStackTrace(trace.*);
                    }
                };
            }
        }

        fn processTag(self: *Self, tag: Tag, y: *f64, event: *const Event) anyerror!void {
            const style = tag.style;
            const g = self.graphics;
            switch (tag.data) {
                .text => |text| {
                    g.setFontSize(style.fontSize);
                    const metrics = g.getTextMetrics(text);

                    switch (event.*) {
                        .mouseButton => |evt| {
                            if (tag.href) |href| {
                                const cx = g.getCursorX();
                                const cy = g.getCursorY();
                                if (!evt.pressed and cx > 0 and cx <= 0 + metrics.width and cy > y.* and cy <= y.* + metrics.height) {
                                    if (self.linkCallback) |cb| {
                                        //var bytes: [1024]u8 align(16) = undefined;
                                        //try cb(self, href);
                                        //var ptr: anyerror!void = undefined;
                                        //try await @asyncCall(&bytes, &ptr, cb, .{self, href});
                                        try cb(self, href);
                                    }
                                }
                            }
                        }
                    }

                    y.* += (metrics.height) * style.lineHeight;
                },
                .container => |childrens| {
                    for (childrens.items) |child| {
                        try self.processTag(child, y, event);
                    }
                }
            }
        }
    };
}