const std = @import("std");
const Stream = std.net.Stream;
const Allocator = std.mem.Allocator;

const c = @cImport({
    @cInclude("openssl/ssl.h");
    @cInclude("openssl/err.h");
});

pub const SSLError = error {
    InitializationError,
    ConnectionError
};

pub const SSLReadError = error {

};

pub const SSLWriteError = error {

};

pub extern "c" var stderr: [*c]c.FILE;

fn print_errors() void {
    c.ERR_print_errors_fp(stderr);
}

fn print_ssl_error(err: c_int) void {
    std.debug.print("detailled error: ", .{});

    switch (err) {
        c.SSL_ERROR_ZERO_RETURN => std.debug.print("SSL_ERROR_ZERO_RETURN\n", .{}),
        c.SSL_ERROR_SSL => std.debug.print("SSL_ERROR_SSL\n", .{}),
        c.SSL_ERROR_SYSCALL => std.debug.print("SSL_ERROR_SYSCALL\n", .{}),
        c.SSL_ERROR_WANT_READ => std.debug.print("SSL_ERROR_WANT_READ\n", .{}),
        c.SSL_ERROR_WANT_WRITE => std.debug.print("SSL_ERROR_WANT_WRITE\n", .{}),
        c.SSL_ERROR_WANT_CONNECT => std.debug.print("SSL_ERROR_WANT_CONNECT\n", .{}),
        c.SSL_ERROR_WANT_ACCEPT => std.debug.print("SSL_ERROR_WANT_ACCEPT\n", .{}),
        else => unreachable
    }
}

pub fn init() SSLError!void {
    //c.ERR_load_crypto_strings();
    //c.OpenSSL_add_all_algorithms();
    //c.OPENSSL_config(null);
    if (c.OPENSSL_init_ssl(0, null) != 1) {
        return error.InitializationError;
    }
    if (c.OPENSSL_init_crypto(c.OPENSSL_INIT_ADD_ALL_CIPHERS | c.OPENSSL_INIT_ADD_ALL_DIGESTS, null) != 1) {
        return error.InitializationError;
    }
}

pub fn deinit() void {
    //c.CONF_modules_unload(1);
    //c.EVP_cleanup();
    //c.CRYPTO_cleanup_all_ex_data();
    //c.ERR_remove_state();
    //c.ERR_free_strings();
}

pub const SSLConnection = struct {
    ctx: *c.SSL_CTX,
    ssl: *c.SSL,
    stream: ?Stream,

    pub const Reader = std.io.Reader(*const SSLConnection, anyerror, read);
    pub const Writer = std.io.Writer(*const SSLConnection, anyerror, write);

    pub fn init(allocator: Allocator, stream: Stream, host: []const u8, secure: bool) !SSLConnection {
        var ctx: *c.SSL_CTX = undefined;
        var ssl: *c.SSL = undefined;

        if (secure) {
            const method = c.TLS_client_method();
            ctx = c.SSL_CTX_new(method) orelse return error.ConnectionError;
            errdefer c.SSL_CTX_free(ctx);
            _ = c.SSL_CTX_set_mode(ctx, c.SSL_MODE_AUTO_RETRY | c.SSL_MODE_ENABLE_PARTIAL_WRITE);

            ssl = c.SSL_new(ctx) orelse return error.ConnectionError;

            var buf = try allocator.dupeZ(u8, host);
            defer allocator.free(buf);

            if (c.SSL_ctrl(ssl, c.SSL_CTRL_SET_TLSEXT_HOSTNAME, c.TLSEXT_NAMETYPE_host_name, buf.ptr) != 1) {
                print_errors();
                return error.ConnectionError;
            }

            if (c.SSL_set_fd(ssl, stream.handle) != 1) {
                print_errors();
                return error.ConnectionError;
            }

            accept: while (true) {
                const result = c.SSL_connect(ssl);
                if (result != 1) {
                    if (result < 0) {
                        const err = c.SSL_get_error(ssl, result);
                        if (err == c.SSL_ERROR_WANT_READ) {
                            var pollfds = [1]std.os.pollfd { .{ .fd=stream.handle, .events=std.os.POLL.IN, .revents=0 } };
                            _ = try std.os.poll(&pollfds, 1000);
                            continue :accept;
                        }
                        print_ssl_error(err);
                    }
                    print_errors();
                    return SSLError.ConnectionError;
                }
                break;
            }
        }

        return SSLConnection {
            .ctx = ctx,
            .ssl = ssl,
            .stream = stream
        };
    }

    pub fn reader(self: *const SSLConnection) Reader {
        return .{
            .context = self
        };
    }

    pub fn writer(self: *const SSLConnection) Writer {
        return .{
            .context = self
        };
    }

    pub fn read(self: *const SSLConnection, data: []u8) anyerror!usize {
        var readed: usize = undefined;
        const result = c.SSL_read_ex(self.ssl, data.ptr, data.len, &readed);
        if (result == 1) {
            return readed;
        } else {
            const err = c.SSL_get_error(self.ssl, result);
            if (err == c.SSL_ERROR_ZERO_RETURN or err == c.SSL_ERROR_SYSCALL) { // connection closed
                return 0;
            } else if (err == c.SSL_ERROR_WANT_READ or err == c.SSL_ERROR_WANT_WRITE) {
                var pollfds = [1]std.os.pollfd { .{ .fd=self.stream.?.handle, .events=std.os.POLL.IN, .revents=0 } };
                _ = try std.os.poll(&pollfds, 1000);
                return try self.read(data);
            }
            print_ssl_error(err);
            return SSLError.ConnectionError;
        }
        return 0;
    }

    pub fn write(self: *const SSLConnection, data: []const u8) anyerror!usize {
        var written: usize = undefined;
        const result = c.SSL_write_ex(self.ssl, data.ptr, data.len, &written);
        if (result == 0) {
            const err = c.SSL_get_error(self.ssl, result);
            if (err == c.SSL_ERROR_WANT_READ or err == c.SSL_ERROR_WANT_WRITE) {
                var pollfds = [1]std.os.pollfd { .{ .fd=self.stream.?.handle, .events=std.os.POLL.IN, .revents=0 } };
                _ = try std.os.poll(&pollfds, 1000);
                return try self.write(data);
            }
            print_ssl_error(err);
            return SSLError.ConnectionError;
        }
        return @intCast(usize, written);
    }

    pub fn deinit(self: *const SSLConnection) void {
        if (self.stream == null) c.SSL_CTX_free(self.ctx);
    }
};
