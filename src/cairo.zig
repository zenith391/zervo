// Cairo backend for Zervo
const c = @import("c.zig");
const std = @import("std");
const Allocator = std.mem.Allocator;
const log = std.log.scoped(.glfw);

pub const WindowError = error {
    InitializationError
};

fn checkError(shader: c.GLuint) void {
    var status: c.GLint = undefined;
    c.glGetShaderiv(shader, c.GL_COMPILE_STATUS, &status);

    if (status != c.GL_TRUE) {
        log.warn("uncorrect shader:\n", .{});
        var buf: [512]u8 = undefined;
        var totalLen: c.GLsizei = undefined;
        c.glGetShaderInfoLog(shader, 512, &totalLen, buf[0..]);
        var totalSize: usize = @bitCast(u32, totalLen);
        log.warn("{s}\n", .{buf[0..totalSize]});
    }
}

const WIDTH = 1000;
const HEIGHT = 700;

pub const FontMetrics = struct {
    ascent: f64,
    descent: f64,
    height: f64
};

pub const TextMetrics = struct {
    width: f64,
    height: f64
};

pub const Cursor = enum {
    Normal,
    Text
};

pub const CairoBackend = struct {
    window: *c.GLFWwindow,
    cairo: *c.cairo_t,
    surface: *c.cairo_surface_t,
    gl_texture: c.GLuint,
    frame_requested: bool,
    previousCursor: Cursor = .Normal,
    /// For animation
    request_next_frame: bool = false,
    mouseButtonCb: ?fn(backend: *CairoBackend, button: MouseButton, pressed: bool) void = null,
    mouseScrollCb: ?fn(backend: *CairoBackend, yOffset: f64) void = null,
    keyTypedCb: ?fn(backend: *CairoBackend, codepoint: u21) void = null,
    keyPressedCb: ?fn(backend: *CairoBackend, key: u32, mods: u32) void = null,
    windowResizeCb: ?fn(backend: *CairoBackend, width: f64, height: f64) void = null,
    userData: usize = 0,
    currentFontDesc: ?*c.PangoFontDescription = null,
    currentFont: *c.PangoFont = undefined,
    textLayout: *c.PangoLayout = undefined,
    textContext: *c.PangoContext,

    pub const BackspaceKey = c.GLFW_KEY_BACKSPACE;
    pub const EnterKey = c.GLFW_KEY_ENTER;

    pub const MouseButton = enum(c_int) {
        Left = c.GLFW_MOUSE_BUTTON_LEFT,
        Right = c.GLFW_MOUSE_BUTTON_RIGHT,
        Middle = c.GLFW_MOUSE_BUTTON_MIDDLE
    };

    export fn windowSizeCallback(window: ?*c.GLFWwindow, width: c_int, height: c_int) void {
        var self = @ptrCast(?*CairoBackend, @alignCast(@alignOf(*CairoBackend), c.glfwGetWindowUserPointer(window))) orelse unreachable;
        c.cairo_destroy(self.cairo);
        c.cairo_surface_destroy(self.surface);
        self.surface = c.cairo_image_surface_create(c.cairo_format_t.CAIRO_FORMAT_ARGB32, width, height) orelse unreachable;
        self.cairo = c.cairo_create(self.surface) orelse unreachable;
        self.frame_requested = true;
        if (self.windowResizeCb) |callback| {
            callback(self, @intToFloat(f64, width), @intToFloat(f64, height));
        }

        // var w: c_int = 0;
        // var h: c_int = 0;
        // c.glfwGetFramebufferSize(self.window, &w, &h);
        // c.glViewport(0, 0, w, h);
        // c.cairo_surface_flush(self.surface);
        // var data = c.cairo_image_surface_get_data(self.surface);
        // c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGB,
        //     c.cairo_image_surface_get_width(self.surface),
        //     c.cairo_image_surface_get_height(self.surface), 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, data);
        // c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
        // c.glfwSwapBuffers(self.window);
    }

    export fn mouseButtonCallback(window: ?*c.GLFWwindow, button: c_int, action: c_int, mods: c_int) void {
        var self = @ptrCast(?*CairoBackend, @alignCast(@alignOf(*CairoBackend), c.glfwGetWindowUserPointer(window))) orelse unreachable;
        if (self.mouseButtonCb) |callback| {
            callback(self, @intToEnum(MouseButton, button), action == c.GLFW_PRESS);
        }
    }

    export fn mouseScrollCallback(window: ?*c.GLFWwindow, xOffset: f64, yOffset: f64) void {
        var self = @ptrCast(?*CairoBackend, @alignCast(@alignOf(*CairoBackend), c.glfwGetWindowUserPointer(window))) orelse unreachable;
        if (self.mouseScrollCb) |callback| {
            callback(self, yOffset);
        }
    }

    export fn characterCallback(window: ?*c.GLFWwindow, codepoint: c_uint) void {
        var self = @ptrCast(?*CairoBackend, @alignCast(@alignOf(*CairoBackend), c.glfwGetWindowUserPointer(window))) orelse unreachable;
        if (self.keyTypedCb) |callback| {
            callback(self, @intCast(u21, codepoint));
        }
    }

    export fn keyCallback(window: ?*c.GLFWwindow, key: c_int, scancode: c_int, action: c_int, mods: c_int) void {
        var self = @ptrCast(?*CairoBackend, @alignCast(@alignOf(*CairoBackend), c.glfwGetWindowUserPointer(window))) orelse unreachable;
        if (action == c.GLFW_PRESS or action == c.GLFW_REPEAT) {
            if (self.keyPressedCb) |callback| {
                callback(self, @bitCast(u32, key), @bitCast(u32, mods));
            }
        }
    }

    pub fn init() !CairoBackend {
        if (c.glfwInit() != 1) {
            log.err("Could not init GLFW!\n", .{});
            return WindowError.InitializationError;
        }
        errdefer c.glfwTerminate();

        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MAJOR, 3);
        c.glfwWindowHint(c.GLFW_CONTEXT_VERSION_MINOR, 2);
        c.glfwWindowHint(c.GLFW_OPENGL_PROFILE, c.GLFW_OPENGL_CORE_PROFILE);
        c.glfwWindowHint(c.GLFW_RESIZABLE, c.GLFW_TRUE);
        const window = c.glfwCreateWindow(WIDTH, HEIGHT, "Test Cairo backend", null, null) orelse return WindowError.InitializationError;

        const surface = c.cairo_image_surface_create(c.cairo_format_t.CAIRO_FORMAT_ARGB32, WIDTH, HEIGHT) orelse return WindowError.InitializationError;
        const cairo = c.cairo_create(surface) orelse return WindowError.InitializationError;

        c.glfwMakeContextCurrent(window);
        _ = c.glfwSetFramebufferSizeCallback(window, windowSizeCallback);
        _ = c.glfwSetMouseButtonCallback(window, mouseButtonCallback);
        _ = c.glfwSetScrollCallback(window, mouseScrollCallback);
        _ = c.glfwSetCharCallback(window, characterCallback);
        _ = c.glfwSetKeyCallback(window, keyCallback);

        var vert: [:0]const u8 =
            \\ #version 150
            \\ in vec2 position;
            \\ in vec2 texcoord;
            \\ out vec2 texCoord;
            \\ void main() {
            \\   gl_Position = vec4(position, 0.0, 1.0);
            \\   texCoord = texcoord;
            \\ }
        ;

        var frag: [:0]const u8 =
            \\ #version 150
            \\ in vec2 texCoord;
            \\ out vec4 outColor;
            \\ uniform sampler2D tex;
            \\ void main() {
            \\   vec4 color = texture(tex, texCoord);
            \\   outColor.r = color.b;
            \\   outColor.g = color.g;
            \\   outColor.b = color.r;
            \\ }
        ;

        const sqLen = 1;
        var vertices = [_]f32 {
            -sqLen, sqLen, 0.0, 0.0,
            -sqLen, -sqLen, 0.0, 1.0,
            sqLen, -sqLen, 1.0, 1.0,
            sqLen, sqLen, 1.0, 0.0
        };

        var elements = [_]c.GLuint {
            0, 1, 2,
            0, 3, 2
        };

        var vbo: c.GLuint = 0;
        c.glGenBuffers(1, &vbo);
        c.glBindBuffer(c.GL_ARRAY_BUFFER, vbo);

        var vao: c.GLuint = 0;
        c.glGenVertexArrays(1, &vao);
        c.glBindVertexArray(vbo);

        var ebo: c.GLuint = 0;
        c.glGenBuffers(1, &ebo);
        c.glBindBuffer(c.GL_ELEMENT_ARRAY_BUFFER, ebo);
        c.glBufferData(c.GL_ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(elements)), elements[0..], c.GL_STATIC_DRAW);

        c.glBufferData(c.GL_ARRAY_BUFFER, @sizeOf(@TypeOf(vertices)), vertices[0..], c.GL_STATIC_DRAW);

        const vertexShader = c.glCreateShader(c.GL_VERTEX_SHADER);
        c.glShaderSource(vertexShader, 1, &vert, null);
        c.glCompileShader(vertexShader);
        checkError(vertexShader);

        const fragmentShader = c.glCreateShader(c.GL_FRAGMENT_SHADER);
        c.glShaderSource(fragmentShader, 1, &frag, null);
        c.glCompileShader(fragmentShader);
        checkError(fragmentShader);

        const shaderProgram = c.glCreateProgram();
        c.glAttachShader(shaderProgram, vertexShader);
        c.glAttachShader(shaderProgram, fragmentShader);
        c.glBindFragDataLocation(shaderProgram, 0, "outColor");
        c.glLinkProgram(shaderProgram);
        c.glUseProgram(shaderProgram);

        const stride = 4 * @sizeOf(f32);
        const posAttrib = c.glGetAttribLocation(shaderProgram, "position");
        c.glVertexAttribPointer(@bitCast(c.GLuint, posAttrib), 2, c.GL_FLOAT, c.GL_FALSE, stride, 0);
        c.glEnableVertexAttribArray(@bitCast(c.GLuint, posAttrib));

        const texAttrib = c.glGetAttribLocation(shaderProgram, "texcoord");
        c.glVertexAttribPointer(@bitCast(c.GLuint, texAttrib), 2, c.GL_FLOAT, c.GL_FALSE, stride, 2*@sizeOf(f32));
        c.glEnableVertexAttribArray(@bitCast(c.GLuint, texAttrib));

        var tex: c.GLuint = 0;
        c.glGenTextures(1, &tex);
        c.glBindTexture(c.GL_TEXTURE_2D, tex);
        c.glPixelStorei(c.GL_UNPACK_ALIGNMENT, 1);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MIN_FILTER, c.GL_NEAREST);
        c.glTexParameteri(c.GL_TEXTURE_2D, c.GL_TEXTURE_MAG_FILTER, c.GL_NEAREST);

        var backend = CairoBackend {
            .frame_requested = true,
            .window = window,
            .gl_texture = tex,
            .cairo = cairo,
            .surface = surface,
            .textContext = c.pango_cairo_create_context(cairo) orelse unreachable
        };
        backend.textLayout = c.pango_layout_new(backend.textContext) orelse unreachable;
        c.pango_layout_set_wrap(backend.textLayout, .PANGO_WRAP_WORD_CHAR);
        backend.setFontFace("Nunito 12");
        c.glfwSetWindowUserPointer(window, &backend);
        return backend;
    }

    /// Return true if loop should continue.
    pub fn update(self: *CairoBackend) bool {
        c.glfwSetWindowUserPointer(self.window, self);
        var width: c_int = 0;
        var height: c_int = 0;
        c.glfwGetFramebufferSize(self.window, &width, &height);
        c.glViewport(0, 0, width, height);
        if (self.frame_requested) {
            c.cairo_surface_flush(self.surface);
            var data = c.cairo_image_surface_get_data(self.surface);
            c.glTexImage2D(c.GL_TEXTURE_2D, 0, c.GL_RGB,
                c.cairo_image_surface_get_width(self.surface),
                c.cairo_image_surface_get_height(self.surface), 0, c.GL_RGBA, c.GL_UNSIGNED_BYTE, data);
            if (self.request_next_frame) {
                self.request_next_frame = false;
            } else {
                self.frame_requested = false;
            }
        }
        c.glDrawElements(c.GL_TRIANGLES, 6, c.GL_UNSIGNED_INT, null);
        std.time.sleep(16*1000000);
        c.glfwSwapBuffers(self.window);
        c.glfwPollEvents();
        return c.glfwWindowShouldClose(self.window) != 1;
    }

    pub fn getCursorX(self: *CairoBackend) f64 {
        var x: f64 = undefined;
        c.glfwGetCursorPos(self.window, &x, null);
        return x;
    }

    pub fn getCursorY(self: *CairoBackend) f64 {
        var y: f64 = undefined;
        c.glfwGetCursorPos(self.window, null, &y);
        return y;
    }

    pub fn setCursor(self: *CairoBackend, cursor: Cursor) void {
        if (cursor == self.previousCursor) return;
        if (cursor == .Normal) {
            c.glfwSetCursor(self.window, null);
        } else {
            const cursorType: c_int = switch (cursor) {
                .Text => c.GLFW_IBEAM_CURSOR,
                .Normal => unreachable
            };
            const glfwCursor = c.glfwCreateStandardCursor(cursorType);
            c.glfwSetCursor(self.window, glfwCursor);
            //c.glfwDestroyCursor(glfwCursor);
        }
        self.previousCursor = cursor;
    }

    pub fn isMousePressed(self: *CairoBackend, btn: MouseButton) bool {
        return c.glfwGetMouseButton(self.window, @enumToInt(btn)) == c.GLFW_PRESS;
    }

    pub fn getWidth(self: *CairoBackend) f64 {
        return @intToFloat(f64, c.cairo_image_surface_get_width(self.surface));
    }

    pub fn getHeight(self: *CairoBackend) f64 {
        return @intToFloat(f64, c.cairo_image_surface_get_height(self.surface));
    }

    pub fn deinit(self: *CairoBackend) void {
        c.cairo_surface_destroy(self.surface);
        c.cairo_destroy(self.cairo);
        c.glfwTerminate();
    }

    // Draw functions
    pub fn fill(self: *CairoBackend) void {
        c.cairo_fill(self.cairo);
    }

    pub fn stroke(self: *CairoBackend) void {
        c.cairo_stroke(self.cairo);
    }

    pub fn setSourceRGB(self: *CairoBackend, r: f64, g: f64, b: f64) void {
        c.cairo_set_source_rgb(self.cairo, r, g, b);
    }

    pub fn setSourceRGBA(self: *CairoBackend, r: f64, g: f64, b: f64, a: f64) void {
        c.cairo_set_source_rgba(self.cairo, r, g, b, a);
    }

    // Path
    pub fn moveTo(self: *CairoBackend, x: f64, y: f64) void {
        c.cairo_move_to(self.cairo, x, y);
    }

    pub fn moveBy(self: *CairoBackend, x: f64, y: f64) void {
        c.cairo_rel_move_to(self.cairo, x, y);
    }

    pub fn lineTo(self: *CairoBackend, x: f64, y: f64) void {
        c.cairo_line_to(self.cairo, x, y);
    }

    pub fn rectangle(self: *CairoBackend, x: f64, y: f64, width: f64, height: f64) void {
        c.cairo_rectangle(self.cairo, x, y, width, height);
    }

    pub fn setTextWrap(self: *CairoBackend, width: ?f64) void {
        c.pango_layout_set_width(self.textLayout, if (width) |w| @floatToInt(c_int, @floor(w*c.PANGO_SCALE)) else -1);
    }

    pub fn text(self: *CairoBackend, str: [:0]const u8) void {
        var inkRect: c.PangoRectangle = undefined;
        c.pango_layout_get_pixel_extents(self.textLayout, null, &inkRect);

        c.cairo_save(self.cairo);
        const dx = @intToFloat(f64, inkRect.x);
        const dy = @intToFloat(f64, inkRect.y);
        c.cairo_rel_move_to(self.cairo, dx, dy);
        c.pango_layout_set_text(self.textLayout, str, @intCast(c_int, str.len));
        c.pango_cairo_update_layout(self.cairo, self.textLayout);
        c.pango_cairo_show_layout(self.cairo, self.textLayout);
        c.cairo_restore(self.cairo);
    }

    pub fn setFontFace(self: *CairoBackend, font: [:0]const u8) void {
        if (self.currentFontDesc != null) {
            c.pango_font_description_free(self.currentFontDesc);
        }
        self.currentFontDesc = c.pango_font_description_from_string(font) orelse unreachable;
        self.currentFont = c.pango_context_load_font(self.textContext, self.currentFontDesc);
        c.pango_layout_set_font_description(self.textLayout, self.currentFontDesc);
    }

    pub fn setFontSize(self: *CairoBackend, size: f64) void {
        c.pango_font_description_set_size(self.currentFontDesc, @floatToInt(c_int, @floor(size * c.PANGO_SCALE)));
        c.pango_layout_set_font_description(self.textLayout, self.currentFontDesc);
        self.currentFont = c.pango_context_load_font(self.textContext, self.currentFontDesc);
    }

    pub fn getFontMetrics(self: *CairoBackend) FontMetrics {
        var metrics: c.cairo_font_extents_t = undefined;
        c.cairo_font_extents(self.cairo, &metrics);
        const metrics = c.pango_font_get_metrics(self.currentFont);
        defer c.pango_font_metrics_unref(metrics);
        return .{
            .ascent = c.pango_font_metrics_get_ascent(metrics),
            .descent = c.pango_font_metrics_get_descent(metrics),
            .height = c.pango_font_metrics_get_height(metrics)
        };
    }

    pub fn getTextMetrics(self: *CairoBackend, str: [:0]const u8) TextMetrics {
        var width: c_int = undefined;
        var height: c_int = undefined;
        c.pango_layout_set_text(self.textLayout, str, @intCast(c_int, str.len));
        c.pango_layout_get_pixel_size(self.textLayout, &width, &height);
        return .{
            .width = @intToFloat(f64, width),
            .height = @intToFloat(f64, height)
        };
    }

    pub fn clear(self: *CairoBackend) void {
        c.cairo_set_source_rgb(self.cairo, 1.0, 1.0, 1.0);
        c.cairo_rectangle(self.cairo, 0, 0, self.getWidth(), self.getHeight());
        c.cairo_fill(self.cairo);
    }
};
