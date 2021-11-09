const std = @import("std");
pub const zgt = @import("zgt");
pub usingnamespace zgt;

pub fn ZervoView() zgt.Canvas_Impl {
    var canvas = zgt.Canvas(.{});
    return canvas;
}

pub const FontMetrics = struct {
    ascent: f64,
    descent: f64,
    height: f64
};

pub const TextMetrics = struct {
    width: f64,
    height: f64
};

pub const GraphicsBackend = struct {
    ctx: zgt.DrawContext,
    layout: ?zgt.DrawContext.TextLayout = null,
    font: zgt.DrawContext.Font = .{ .face = "monospace", .size = 12.0 },
    request_next_frame: bool = false,
    x: f64 = 0,
    y: f64 = 0,
    cursorX: f64 = 0,
    cursorY: f64 = 0,
    width: f64 = 0,
    height: f64 = 0,
    userData: usize = 0,
    frame_requested: bool = false,

    pub const MouseButton = enum(u2) {
        Left = 0,
        Right = 1,
        Middle = 2,
    };

    pub fn getCursorX(self: *GraphicsBackend) f64 {
        return self.cursorX;
    }

    pub fn getCursorY(self: *GraphicsBackend) f64 {
        return self.cursorY;
    }

    pub fn getWidth(self: *GraphicsBackend) f64 {
        return self.width;
    }

    pub fn getHeight(self: *GraphicsBackend) f64 {
        return self.height;
    }

    // Draw functions
    pub fn fill(self: *GraphicsBackend) void {
        self.ctx.fill();
    }

    pub fn stroke(self: *GraphicsBackend) void {
        _ = self;
        unreachable; // TODO
    }

    pub fn setSourceRGB(self: *GraphicsBackend, r: f64, g: f64, b: f64) void {
        self.setSourceRGBA(r, g, b, 1.0);
    }

    pub fn setSourceRGBA(self: *GraphicsBackend, r: f64, g: f64, b: f64, a: f64) void {
        self.ctx.setColorRGBA(@floatCast(f32, r), @floatCast(f32, g), @floatCast(f32, b), @floatCast(f32, a));
    }

    // Path
    pub fn moveTo(self: *GraphicsBackend, x: f64, y: f64) void {
        self.x = x;
        self.y = y;
    }

    pub fn moveBy(self: *GraphicsBackend, x: f64, y: f64) void {
        self.x += x;
        self.y += y;
    }

    pub fn lineTo(self: *GraphicsBackend, x: f64, y: f64) void {
        _ = self;
        _ = x;
        _ = y;
        unreachable; // TODO
    }

    pub fn rectangle(self: *GraphicsBackend, x: f64, y: f64, width: f64, height: f64) void {
        self.ctx.rectangle(
            @floatToInt(u32, @floor(x)), @floatToInt(u32, @floor(y)),
            @floatToInt(u32, @floor(width)), @floatToInt(u32, @floor(height)));
    }

    pub fn setTextWrap(self: *GraphicsBackend, width: ?f64) void {
        if (self.layout == null) {
            self.layout = zgt.DrawContext.TextLayout.init();
        }
        self.layout.?.wrap = width;
    }

    pub fn text(self: *GraphicsBackend, str: [:0]const u8) void {
        if (self.layout == null) {
            self.layout = zgt.DrawContext.TextLayout.init();
        }
        self.ctx.text(@floatToInt(i32, @floor(self.x)), @floatToInt(i32, @floor(self.y)),
            self.layout.?, str);
    }

    pub fn setFontFace(self: *GraphicsBackend, font: [:0]const u8) void {
        if (self.layout == null) {
            self.layout = zgt.DrawContext.TextLayout.init();
        }
        self.font.face = font;
        self.layout.?.setFont(self.font);
    }

    pub fn setFontSize(self: *GraphicsBackend, size: f64) void {
        if (self.layout == null) {
            self.layout = zgt.DrawContext.TextLayout.init();
        }
        self.font.size = size;
        self.layout.?.setFont(self.font);
    }

    pub fn getFontMetrics(self: *GraphicsBackend) FontMetrics {
        _ = self;
        @panic("unimplemented");
        //return undefined;
    }

    pub fn getTextMetrics(self: *GraphicsBackend, str: [:0]const u8) TextMetrics {
        _ = str;
        const metrics = self.layout.?.getTextSize(str);
        return TextMetrics {
            .width = @intToFloat(f64, metrics.width),
            .height = @intToFloat(f64, metrics.height)
        };
    }

    pub fn clear(self: *GraphicsBackend) void {
        self.setSourceRGB(1.0, 1.0, 1.0);
        self.rectangle(0, 0, self.getWidth(), self.getHeight());
        self.fill();
    }
};
