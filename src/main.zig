const zervo = @import("zervo");
const std = @import("std");
const ssl = @import("ssl");
const GraphicsBackend = @import("cairo.zig").CairoBackend;
const RenderContext = zervo.renderer.RenderContext(GraphicsBackend);
const imr = zervo.markups.imr;
const os = std.os;
const net = std.net;
const warn = std.debug.warn;
const Allocator = std.mem.Allocator;

//pub const io_mode = .evented;

const DISABLE_IPV6 = false;

var gpa = std.heap.GeneralPurposeAllocator(.{}) {};
const allocator = &gpa.allocator;
var currentUrl: ?zervo.Url = null;

var addressBar: [:0]u8 = undefined;
var addressBarFocused: bool = false;

var renderCtx: RenderContext = undefined;

var firstLoad: bool = true;

const LoadResult = union(enum) {
    Document: imr.Document,
    Download: []const u8
};

const LoadErrorDetails = union(enum) {
    Input: []const u8
};

fn loadHttp(addr: net.Address, url: zervo.Url) !imr.Document {
    var headers = zervo.protocols.http.HeaderMap.init(allocator);
    try headers.put("Connection", .{
        .value = "close"
    });
    try headers.put("User-Agent", .{
        .value = "Mozilla/5.0 (X11; Linux x86_64; rv:1.0) Gecko/20100101 TestAmabob/1.0"
    });
    defer headers.deinit();

    var response = try zervo.protocols.http.request(allocator, addr, .{
        .host = url.host,
        .path = url.path,
        .headers = headers,
        .secure = true
    });
    defer response.deinit();

    const doc = try zervo.markups.html.parse_imr(allocator, response.content);
    return doc;
}

fn loadGemini(addr: net.Address, url: zervo.Url, loadErrorDetails: *LoadErrorDetails) !LoadResult {
    var errorDetails: zervo.protocols.gemini.GeminiErrorDetails = undefined;
    var response = zervo.protocols.gemini.request(allocator, addr, url, &errorDetails) catch |err| switch (err) {
        error.KnownError, error.InputRequired => {
            errorDetails.deinit();
            switch (errorDetails) {
                .Input => |input| {
                    return error.InputRequired;
                },
                .PermanentFailure => |failure| {
                    return error.NotFound;
                },
                else => unreachable
            }
        },
        else => return err
    };
    defer response.deinit();

    if (response.statusCode != 20 and false) {
        std.log.err("Request error:\nStatus code: {} {s}", .{response.statusCode, response.meta});
        return zervo.protocols.gemini.GeminiError.InvalidStatus;
    }

    const mime = response.meta;
    if (try zervo.markups.from_mime(allocator, url, mime, response.content)) |doc| {
        return LoadResult {
            .Document = doc
        };
    } else {
        return LoadResult {
            .Download = try allocator.dupe(u8, response.content)
        };
    }
}

fn loadPage(url: zervo.Url) !LoadResult {
    std.log.debug("Loading web page at {} host = {s}", .{url, url.host});

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
    std.log.debug("Resolved address of {s}: {}", .{url.host, addr});

    if (std.mem.eql(u8, url.scheme, "gemini")) {
        var details: LoadErrorDetails = undefined;
        const doc = try loadGemini(addr, url, &details);
        return doc;
    } else {
        std.log.err("No handler for URL scheme {s}", .{url.scheme});
        return error.UnhandledUrlScheme;
    }
}

fn loadPageChecked(url: zervo.Url) ?LoadResult {
    const doc = loadPage(url) catch |err| {
        const name = @errorName(err);
        const path = std.mem.concat(allocator, u8, &[_][]const u8 {"res/errors/", name, ".gmi"}) catch unreachable;
        defer allocator.free(path);

        const file = std.fs.cwd().openFile(path, .{}) catch |e| {
            std.log.err("Missing error page for error {s}", .{@errorName(err)});
            if (@errorReturnTrace()) |trace| {
                std.debug.dumpStackTrace(trace.*);
            }
            return null;
        };

        const full = file.readToEndAlloc(allocator, std.math.maxInt(usize)) catch unreachable;
        const errorDoc = zervo.markups.gemini.parse(allocator, url, full) catch unreachable;
        return LoadResult { .Document = errorDoc };
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
                ctx.layout();
                ctx.offsetY = 0;
                ctx.offsetYTarget = 0;
                firstLoad = false;
            },
            .Download => |content| {
                defer allocator.free(content);

                const lastSlash = std.mem.lastIndexOfScalar(u8, url.path, '/').?;
                const name = url.path[lastSlash+1..];
                const file = try std.fs.cwd().createFile(name, .{});
                try file.writeAll(content);
                file.close();
                std.log.info("Saved to {s}", .{name});

                var xdg = try std.ChildProcess.init(&[_][]const u8 {"xdg-open", name}, allocator);
                defer xdg.deinit();
                _ = try xdg.spawnAndWait();
            }
        }
    }
}

fn keyPressed(backend: *GraphicsBackend, key: u32, mods: u32) void {
    if (addressBarFocused) {
        if (key == GraphicsBackend.BackspaceKey) {
            if (addressBar.len > 0) {
                const len = addressBar.len;
                addressBar[len-1] = 0;
                addressBar = allocator.shrink(addressBar, len)[0..len-1 :0];
                backend.frame_requested = true;
            }
        } else if (key == GraphicsBackend.EnterKey) {
            const url = zervo.Url.parse(addressBar) catch |err| switch (err) {
                else => {
                    std.log.warn("invalid url", .{});
                    return;
                }
            };
            openPage(&renderCtx, url) catch unreachable;
            backend.frame_requested = true;
        }
    } else {
        if (key == GraphicsBackend.UpKey) {
            RenderContext.scrollPage(backend, true);
        } else if (key == GraphicsBackend.DownKey) {
            RenderContext.scrollPage(backend, false);
        }
    }
}

fn keyTyped(backend: *GraphicsBackend, codepoint: u21) void {
    if (addressBarFocused) {
        var codepointOut: [4]u8 = undefined;
        const codepointLength = std.unicode.utf8Encode(codepoint, &codepointOut) catch unreachable;
        const utf8 = codepointOut[0..codepointLength];
        const new = std.mem.concat(allocator, u8, &[_][]const u8 {addressBar, utf8}) catch unreachable;
        const newZ = allocator.dupeZ(u8, new) catch unreachable;
        defer allocator.free(new);
        allocator.free(addressBar);
        addressBar = newZ;
        backend.frame_requested = true;
    }
}

fn mouseButton(backend: *GraphicsBackend, button: GraphicsBackend.MouseButton, pressed: bool) void {
    const cx = backend.getCursorX();
    const cy = backend.getCursorY();

    if (cx > 80 and cy > 10 and cx < backend.getWidth() - 10 and cy < 10 + 30) {
        addressBarFocused = true;
    } else {
        addressBarFocused = false;
    }

    RenderContext.mouseButtonCallback(backend, button, pressed);
}

fn windowResize(backend: *GraphicsBackend, width: f64, height: f64) void {
    renderCtx.layout();
}

// Main function
pub fn main() !void {
    defer _ = gpa.deinit();

    // Initialize OpenSSL.
    try ssl.init();
    defer ssl.deinit();

    // Example URLs:
    //  gemini://gemini.circumlunar.space/
    //  gemini://drewdevault.com/
    //  gemini://skyjake.fi/lagrange/
    const url = try zervo.Url.parse("gemini://gemini.circumlunar.space/");

    var backend = try GraphicsBackend.init();
    renderCtx = RenderContext { .graphics = &backend, .document = undefined, .linkCallback = openPage, .allocator = allocator };

    renderCtx.setup();
    renderCtx.y = 50;

    try openPage(&renderCtx, url);
    defer renderCtx.document.deinit();
    defer allocator.free(addressBar);
    defer currentUrl.?.deinit();

    backend.keyTypedCb = keyTyped;
    backend.keyPressedCb = keyPressed;
    backend.mouseButtonCb = mouseButton;
    backend.windowResizeCb = windowResize;

    while (true) {
        if (backend.frame_requested) {
            const g = &backend;
            g.clear();
            renderCtx.render();

            g.moveTo(0, 0);
            g.setSourceRGB(0.5, 0.5, 0.5);
            g.rectangle(0, 0, g.getWidth(), 50);
            g.fill();
            g.setSourceRGB(0.1, 0.1, 0.1);
            g.rectangle(80, 10, g.getWidth() - 90, 30);
            g.fill();

            if (currentUrl) |u| {
                g.moveTo(90, 14);
                g.setFontFace("Nunito");
                g.setFontSize(10);
                g.setTextWrap(null);
                g.setSourceRGB(1, 1, 1);
                g.text(addressBar);
                g.stroke();
            }
        }

        const g = &backend;
        const cx = g.getCursorX();
        const cy = g.getCursorY();

        if (cx > 80 and cy > 10 and cx < g.getWidth() - 10 and cy < 10 + 30) {
            g.setCursor(.Text);
        } else {
            g.setCursor(.Normal);
        }

        if (!backend.update()) {
            break;
        }
    }

    backend.deinit();
}
