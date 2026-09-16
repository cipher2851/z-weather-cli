const std = @import("std");

/// Robust helper to extract value by key from simple JSON
fn extractValue(body: []const u8, key: []const u8) []const u8 {
    if (std.mem.indexOf(u8, body, "\"") ) |first_quote| {
        var i = first_quote;
        while (i < body.len) {
            if (std.mem.indexOf(u8, body[i..], "\"") ) |rel_start| {
                const abs_start = i + rel_start;
                const end_quote_rel = std.mem.indexOf(u8, body[abs_start + 1..], "\"") orelse break;
                const abs_end = abs_start + 1 + end_quote_rel;
                
                if (std.mem.eql(u8, body[abs_start + 1..abs_end], key)) {
                    var val_start = abs_end + 1;
                    
                    // Find the colon
                    while (val_start < body.len and body[val_start] != ':') {
                        val_start += 1;
                    }
                    if (val_start >= body.len) return "";
                    val_start += 1; // skip ':'

                    // Skip whitespace
                    while (val_start < body.len and (body[val_start] == ' ' or body[val_start] == '\t' or body[val_start] == '\n' or body[val_start] == '\r')) {
                        val_start += 1;
                    }

                    if (val_start >= body.len) return "";

                    var val_end = val_start;
                    while (val_end < body.len) {
                        const c = body[val_end];
                        if (c == ',' or c == '}' or c == ']' or c == '\n' or c == '\r') break;
                        val_end += 1;
                    }

                    var result = body[val_start..val_end];
                    // Trim potential trailing spaces
                    while (result.len > 0 and (result[result.len - 1] == ' ' or result[result.len - 1] == '\t')) {
                        result = result[0..result.len - 1];
                    }
                    // Trim quotes for string values
                    if (result.len >= 2 and result[0] == '"' and result[result.len - 1] == '"') {
                        result = result[1..result.len - 1];
                    }
                    return result;
                }
                i = abs_end + 1;
            } else {
                break;
            }
        }
    }
    return "";
}

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const stdout = std.io.getStdOut().writer();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    var lat: []const u8 = "52.52";
    var lon: []const u8 = "13.41";
    var location_name: []const u8 = "Berlin";

    var i: usize = 0;
    while (i < args.len) : (i += 1) {
        if (std.mem.eql(u8, args[i], "--lat") && i + 2 < args.len) {
            lat = args[i + 1];
            lon = args[i + 2];
            location_name = "specified coordinates";
            i += 2;
        } else if (i == 1 && args.len >= 3 && !std.mem.eql(u8, args[1], "--lat")) {
            lat = args[1];
            lon = args[2];
            location_name = "specified coordinates";
            i += 2;
        }
    }

    const url = try std.fmt.allocPrint(allocator, "https://api.open-meteo.com/v1/forecast?latitude={s}&longitude={s}&current_weather=true", .{ lat, lon });
    defer allocator.free(url);

    try stdout.print("Fetching current weather for {s} ({s}, {s})...\n", .{ location_name, lat, lon });

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var server_header_buffer: [1024]u8 = undefined;
    
    var request = try client.open(.GET, url, .{ .response_headers_buffer = &server_header_buffer });
    defer request.deinit();

    try request.send();
    try request.wait();

    var response_body = std.ArrayList(u8).init(allocator);
    defer response_body.deinit();

    while (try request.read()) |chunk| {
        try response_body.appendSlice(chunk);
    }

    const body = response_body.items;
    
    if (std.mem.indexOf(u8, body, "\"current_weather\":") != null) {
        const temp = extractValue(body, "temperature");
        const wind = extractValue(body, "windspeed");
        
        try stdout.print("\n--- Weather Report ---\n", .{});
        try stdout.print("Location    : {s}\n", .{location_name});
        try stdout.print("Temperature : {s}°C\n", .{temp});
        try stdout.print("Windspeed   : {s} km/h\n", .{wind});
        try stdout.print("---------------------\n", .{});
    } else {
        try stdout.print("Failed to find weather data in response.\n", .{});
        try stdout.print("Response: {s}\n", .{body});
    }
}