const std = @import("std");
const net = std.net; //net is std.net and import std
const heap = std.heap;
const posix = std.posix; //get posix
var gpa_instance = std.heap.DebugAllocator(.{}).init;

pub fn main() !void {
    const gpa_alloc = gpa_instance.allocator();
    defer _ = gpa_instance.deinit();
    var buffer = std.ArrayList(u8).init(gpa_alloc);

    const sock_fd = try posix.socket(posix.AF.INET, posix.SOCK.STREAM, 0);
    defer posix.close(sock_fd);

    const addr = net.Address.initIp4([4]u8{ 127, 0, 0, 1 }, 9092);
    try posix.bind(sock_fd, &addr.any, addr.getOsSockLen());
    try posix.listen(sock_fd, 1);

    // You can use print statements as follow for debugging, they'll be visible when running tests.
    std.debug.print("Logs from your program will appear here!\n", .{});

    // Uncomment this block to pass the first stage
    while (true) {
        defer buffer.clearRetainingCapacity();
        var client_addr: posix.sockaddr = undefined;
        var client_addr_len: posix.socklen_t = @sizeOf(posix.sockaddr);
        const client_sockfd = try posix.accept(sock_fd, &client_addr, &client_addr_len, posix.SOCK.CLOEXEC);
        //pretty interesting so message size which is a 32 bit integer
        var read_buffer: [14]u8 = undefined;
        _ = try posix.read(client_sockfd, &read_buffer);
        const Request = struct { message_size: u32, API_KEY: u16, API_VERSION: u16, correlation_id: u32, contents: u8, TAG_BUFFER: u8 };
        const req = Request{ .message_size = std.mem.readInt(u32, read_buffer[0..4], .big), .API_KEY = std.mem.readInt(u16, read_buffer[4..6], .big), .API_VERSION = std.mem.readInt(u16, read_buffer[6..8], .big), .correlation_id = std.mem.readInt(u32, read_buffer[8..12], .big), .contents = std.mem.readInt(u8, read_buffer[12..13], .big), .TAG_BUFFER = 0 };
        std.debug.print("Reading the data from the client", .{});
        const Response = struct { message_size: u32, correlation_id: u32, error_code: u16, api_key: u16 };
        var code: u16 = 0;
        if (req.API_VERSION > 4) {
            code = 35;
        }
        if (req.API_VERSION <= 0) {
            code = 35;
        }
        const res: Response = Response{ .message_size = @intCast(@sizeOf(Response)), .correlation_id = req.correlation_id, .error_code = code, .api_key = 4 };
        const Entry = struct { api_key: i16, min: i16, max: i16, TAG_BUFFER: i8 };
        const Entries = [_]Entry{.{ .api_key = 18, .min = 0, .max = 4, .TAG_BUFFER = 0 }};
        try buffer.appendSlice(std.mem.asBytes(&@byteSwap(res.message_size)));
        try buffer.appendSlice(std.mem.asBytes(&@byteSwap(res.correlation_id)));
        try buffer.appendSlice(std.mem.asBytes(&@byteSwap(res.error_code)));
        // try buffer.appendSlice(std.mem.asBytes(&@byteSwap(res.api_key)));
        try buffer.append(Entries.len + 1);
        for (Entries) |entry| {
            try buffer.appendSlice(std.mem.asBytes(&@byteSwap(entry.api_key)));
            try buffer.appendSlice(std.mem.asBytes(&@byteSwap(entry.min)));
            try buffer.appendSlice(std.mem.asBytes(&@byteSwap(entry.max)));
            try buffer.append(0);
        }
        const final_tag: u8 = 0;
        try buffer.appendNTimes(0, 4); //throttletime in ms
        try buffer.appendSlice(std.mem.asBytes(&@byteSwap(final_tag))); //tag buffer
        const length: u32 = @intCast(buffer.items.len - 4);
        std.mem.writeInt(u32, buffer.items[0..4], length, .big);
        _ = try posix.write(client_sockfd, buffer.items);
    }
}
