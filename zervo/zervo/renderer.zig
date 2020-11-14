pub const std = @import("std");
pub const imr = @import("markups/imr.zig");
const Document = imr.Document;
const Tag = imr.Tag;

pub fn render(comptime T: type, g: *T, document: Document) void {
    g.setSourceRGB(1, 1, 1);
    g.rectangle(0, 0, g.getWidth(), g.getHeight());
    g.fill();

    var y: f64 = 0;
    for (document.tags.items) |tag| {
        renderTag(T, g, tag, &y);
        if (std.event.Loop.instance) |loop| {
            //std.debug.warn("yield\n", .{});
            //loop.yield();
        }
    }
    g.*.frame_requested = true;
}

fn setColor(comptime T: type, g: *T, color: imr.Color) void {
    const red = @intToFloat(f64, color.red) / 255.0;
    const green = @intToFloat(f64, color.green) / 255.0;
    const blue = @intToFloat(f64, color.blue) / 255.0;
    g.setSourceRGB(red, green, blue);
}

fn renderTag(comptime T: type, g: *T, tag: Tag, y: *f64) void {
    const style = tag.style;
    switch (tag.data) {
        .text => |text| {
            if (style.textColor) |color| {
                setColor(T, g, color);
            } else {
                g.setSourceRGB(0, 0, 0);
            }
            g.setFontSize(style.fontSize);
            const metrics = g.getTextMetrics(text);
            g.moveTo(0, y.* + metrics.height);
            g.text(text);
            g.stroke();
            y.* += (style.fontSize) * style.lineHeight;
        },
        .container => |childrens| {
            for (childrens.items) |child| {
                renderTag(T, g, child, y);
            }
        }
    }
}