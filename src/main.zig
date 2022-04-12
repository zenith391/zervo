const zervo = @import("zervo");
const std = @import("std");
const ssl = @import("ssl");
const RenderContext = zervo.renderer.RenderContext(GraphicsBackend);
const imr = zervo.markups.imr;
const os = std.os;
const net = std.net;
const Allocator = std.mem.Allocator;

const zgt = @import("zgt.zig");
const GraphicsBackend = zgt.GraphicsBackend;

const DISABLE_IPV6 = false;

var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
var currentUrl: ?zervo.Url = null;

var addressBar: [:0]u8 = undefined;
var addressBarFocused: bool = false;

var renderCtx: RenderContext = undefined;

var firstLoad: bool = true;

const LoadResult = union(enum) { Document: imr.Document, Download: []const u8 };

const LoadErrorDetails = union(enum) { Input: []const u8 };

fn loadGemini(addr: net.Address, url: zervo.Url, loadErrorDetails: *LoadErrorDetails) !LoadResult {
    _ = loadErrorDetails;
    var errorDetails: zervo.protocols.gemini.GeminiErrorDetails = undefined;
    var response = zervo.protocols.gemini.request(allocator, addr, url, &errorDetails) catch |err| switch (err) {
        error.KnownError, error.InputRequired => {
            errorDetails.deinit();
            switch (errorDetails) {
                .Input => {
                    return error.InputRequired;
                },
                .PermanentFailure => {
                    return error.NotFound;
                },
                else => unreachable,
            }
        },
        else => return err,
    };
    defer response.deinit();

    if (response.statusCode != 20 and false) {
        std.log.err("Request error:\nStatus code: {} {s}", .{ response.statusCode, response.meta });
        return zervo.protocols.gemini.GeminiError.InvalidStatus;
    }

    const mime = response.meta;
    if (try zervo.markups.from_mime(allocator, url, mime, response.content)) |doc| {
        return LoadResult{ .Document = doc };
    } else {
        return LoadResult{ .Download = try allocator.dupe(u8, response.content) };
    }
}

fn loadHttps(addr: net.Address, url: zervo.Url, loadErrorDetails: *LoadErrorDetails) !LoadResult {
    _ = loadErrorDetails;
    var headers = zervo.protocols.http.HeaderMap.init(allocator);
    defer headers.deinit();
    try headers.put("Connection", "close");

    const rst = zervo.protocols.http.HttpRequest{ .headers = headers, .secure = true, .host = url.host, .path = url.path };
    var response = zervo.protocols.http.request(allocator, addr, rst) catch |err| switch (err) {
        else => return err,
    };
    defer response.deinit();

    const mime = response.headers.get("Content-Type") orelse "text/html";
    std.log.info("mime: {s}", .{mime});
    if (try zervo.markups.from_mime(allocator, url, mime, response.content)) |doc| {
        return LoadResult{ .Document = doc };
    } else {
        return LoadResult{ .Download = try allocator.dupe(u8, response.content) };
    }
}

fn loadPage(url: zervo.Url) !LoadResult {
    std.log.debug("Loading web page at {} host = {s}", .{ url, url.host });

    var defaultPort: u16 = 80;
    if (std.mem.eql(u8, url.scheme, "gemini")) defaultPort = 1965;
    if (std.mem.eql(u8, url.scheme, "https")) defaultPort = 443;

    const list = try net.getAddressList(allocator, url.host, url.port orelse defaultPort);
    defer list.deinit();
    if (list.addrs.len == 0) return error.UnknownHostName;
    var addr = list.addrs[0];
    if (DISABLE_IPV6) {
        var i: u32 = 1;
        while (addr.any.family == os.AF_INET6) : (i += 1) {
            addr = list.addrs[i];
        }
    }
    std.log.debug("Resolved address of {s}: {}", .{ url.host, addr });

    if (std.mem.eql(u8, url.scheme, "gemini")) {
        var details: LoadErrorDetails = undefined;
        const doc = try loadGemini(addr, url, &details);
        return doc;
    } else if (std.mem.eql(u8, url.scheme, "https")) {
        var details: LoadErrorDetails = undefined;
        const doc = try loadHttps(addr, url, &details);
        return doc;
    } else {
        std.log.err("No handler for URL scheme {s}", .{url.scheme});
        return error.UnhandledUrlScheme;
    }
}

fn loadPageChecked(url: zervo.Url) ?LoadResult {
    const doc = loadPage(url) catch |err| {
        const name = @errorName(err);
        const path = std.mem.concat(allocator, u8, &[_][]const u8{ "res/errors/", name, ".gmi" }) catch unreachable;
        defer allocator.free(path);

        const file = std.fs.cwd().openFile(path, .{}) catch {
            std.log.err("Missing error page for error {s}", .{@errorName(err)});
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
            return null;
        };

        const full = file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch unreachable;
        const errorDoc = zervo.markups.gemini.parse(allocator, url, full) catch unreachable;
        return LoadResult{ .Document = errorDoc };
    };
    return doc;
}

// Handlers
fn openPage(ctx: *RenderContext, url: zervo.Url) !void {
    if (loadPageChecked(url)) |result| {
        switch (result) {
            .Document => |doc| {
                if (currentUrl) |u| {
                    u.deinit();
                }
                currentUrl = try url.dupe(allocator);
                if (!firstLoad) allocator.free(addressBar);
                addressBar = try std.fmt.allocPrintZ(allocator, "{}", .{currentUrl});
                if (!firstLoad) ctx.document.deinit();
                ctx.document = doc;
                ctx.layout_requested = true;
                ctx.offsetY = 0;
                ctx.offsetYTarget = 0;
                firstLoad = false;
            },
            .Download => |content| {
                defer allocator.free(content);

                const lastSlash = std.mem.lastIndexOfScalar(u8, url.path, '/').?;
                var name = url.path[lastSlash + 1 ..];
                if (std.mem.eql(u8, name, "")) {
                    name = "index";
                }
                const file = try std.fs.cwd().createFile(name, .{});
                try file.writeAll(content);
                file.close();
                std.log.info("Saved to {s}", .{name});

                var xdg = try std.ChildProcess.init(&[_][]const u8{ "xdg-open", name }, allocator);
                defer xdg.deinit();
                _ = try xdg.spawnAndWait();
            },
        }
    }
}

fn windowResize(_: *GraphicsBackend, _: f64, _: f64) void {
    renderCtx.layout_requested = true;
}

var backend: GraphicsBackend = GraphicsBackend{ .ctx = undefined };
var setupped: bool = false;

pub fn draw(widget: *zgt.Canvas_Impl, ctx: *zgt.DrawContext) !void {
    backend.ctx = ctx;
    const width = @intToFloat(f64, widget.getWidth());
    const height = @intToFloat(f64, widget.getHeight());
    if (backend.width != width or backend.height != height) {
        renderCtx.layout_requested = true;
    }
    backend.width = width;
    backend.height = height;
    backend.clear();
    renderCtx.graphics = &backend;
    if (!setupped) {
        renderCtx.setup();
        setupped = true;
    }
    renderCtx.render();
}

pub fn mouseButton(_: *zgt.Canvas_Impl, button: zgt.MouseButton, pressed: bool, x: u32, y: u32) !void {
    _ = button;
    backend.cursorX = @intToFloat(f64, x);
    backend.cursorY = @intToFloat(f64, y);
    RenderContext.mouseButtonCallback(&backend, .Left, pressed);
}

pub fn mouseScroll(_: *zgt.Canvas_Impl, _: f32, dy: f32) !void {
    RenderContext.mouseScrollCallback(&backend, -dy);
}

pub fn main() !void {
    try zgt.backend.init();
    defer _ = gpa.deinit();

    var window = try zgt.Window.init();
    try ssl.init();
    defer ssl.deinit();

    const url = try zervo.Url.parse("gemini://gemini.circumlunar.space/");
    //const url = try zervo.Url.parse("https://bellard.org/quickjs/");

    renderCtx = RenderContext{
        .graphics = undefined,
        .document = undefined,
        .linkCallback = openPage,
        .allocator = allocator,
    };
    try openPage(&renderCtx, url);
    defer renderCtx.document.deinit();
    defer currentUrl.?.deinit();

    var view = zgt.ZervoView();
    _ = try view.addDrawHandler(draw);
    try view.addMouseButtonHandler(mouseButton);
    try view.addScrollHandler(mouseScroll);
    try window.set(zgt.Column(.{}, .{
        zgt.Row(.{}, .{
            zgt.TextField(.{ .text = "gemini://gemini.circumlunar.space/" }),
        }),
        zgt.Expanded(&view),
    }));

    window.resize(800, 600);
    window.show();
    while (zgt.stepEventLoop(.Asynchronous)) {
        if (backend.request_next_frame) {
            backend.frame_requested = true;
            backend.request_next_frame = false;
        }

        if (backend.frame_requested) {
            try view.requestDraw();
            backend.frame_requested = false;
        }
        std.time.sleep(16 * std.time.ns_per_ms);
    }
}
