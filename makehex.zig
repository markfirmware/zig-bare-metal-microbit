pub fn main() !void {
    const cwd = fs.cwd();
    const image = try cwd.openFile("zig-out/bin/main.img", fs.File.OpenFlags{});
    defer image.close();
    const hex = try cwd.createFile("main.hex", fs.File.CreateFlags{});
    defer hex.close();
    var offset: usize = 0;
    var read_buf: [4 * 1024 * 1024]u8 = undefined;
    assert(read_buf.len % 32 == 0);
    while (true) {
        var n = try image.read(&read_buf);
        if (n == 0) {
            break;
        }
        while (offset < n) {
            if (offset % 0x10000 == 0) {
                try writeRecord(hex, 0, 0x04, &[_]u8{ @truncate(u8, offset >> 24), @truncate(u8, offset >> 16) });
            }
            const i = math.min(32, n - offset);
            try writeRecord(hex, offset % 0x10000, 0x00, read_buf[offset .. offset + i]);
            offset += i;
        }
    }
    try writeRecord(hex, 0, 0x01, &[_]u8{});
}

fn writeRecord(file: fs.File, offset: usize, code: u8, bytes: []u8) !void {
    var record_buf: [1 + 2 + 1 + 32 + 1]u8 = undefined;
    var record: []u8 = record_buf[0 .. 1 + 2 + 1 + bytes.len + 1];
    record[0] = @truncate(u8, bytes.len);
    record[1] = @truncate(u8, offset >> 8);
    record[2] = @truncate(u8, offset >> 0);
    record[3] = code;
    for (bytes) |b, i| {
        record[4 + i] = b;
    }
    var checksum: u8 = 0;
    for (record[0 .. record.len - 1]) |b| {
        checksum = checksum -% b;
    }
    record[record.len - 1] = checksum;
    var line_buf: [1 + record_buf.len * 2 + 1]u8 = undefined;
    _ = try file.write(try fmt.bufPrint(&line_buf, ":{s}\n", .{std.fmt.fmtSliceHexUpper(record)}));
}

const assert = std.debug.assert;
const fmt = std.fmt;
const fs = std.fs;
const math = std.math;
const std = @import("std");
