const std = @import("std");

/// Maps WMO Weather interpretation codes to human-readable strings
fn getWeatherCondition(code: []const u8) []const u8 {
    if (std.mem.eql(u8, code, "0")) return "Clear sky";
    if (std.mem.eql(u8, code, "1")) return "Mainly clear";
    if (std.mem.eql(u8, code, "2")) return "Partly cloudy";
    if (std.mem.eql(u8, code, "3")) return "Overcast";
    if (std.mem.eql(u8, code, "45")) return "Foggy";
    if (std.mem.eql(u8, code, "48")) return "Rime fog";
    if (std.mem.eql(u8, code, "51")) return "Light drizzle";
    if (std.mem.eql(u8, code, "61")) return "Slight rain";
    if (std.mem.eql(u8, code, "63")) return "Moderate rain";
    if (std.mem.eql(u8, code, "65")) return "Heavy rain";
    if (std.mem.eql(u8, code, "71")) return "Slight snow";
    if (std.mem.eql(u8, code, "73")) return "Moderate snow";
    if (std.mem.eql(u8, code, "75")) return "Heavy snow";
    if (std.mem.eql(u8, code, "80")) return "Slight rain showers";
    if (std.mem.eql(u8, code, "81")) return "Moderate rain showers";
    if (std.mem.eql(u8, code, "82")) return "Violent rain showers";
    if (std.mem.eql(u8, code, "95")) return "Thunderstorm";
    return "Unknown";
}

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
    var use_fahrenheit = false;

    if (args.len > 1) {
        if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
            try stdout.print("Usage: z-weather-cli [options]\n\nOptions:\n  --lat <lat> <lon>  Specify latitude and longitude\n  --unit <C|F>       Temperature unit (C for Celsius, F for Fahrenheit)\n  --help, -h         Show this help message\n\nExample:\n  z-weather-cli --lat 40.71 -74.00 --unit F\n", .{});
            return;
        }

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            if (std.mem.eql(u8, args[i], "--lat") && i + 2 < args.len) {
                lat = args[i + 1];
                lon = args[i + 2];
                location_name = "specified coordinates";
                i += 2;
            } else if (std.mem.eql(u8, args[i], "--unit") && i + 1 < args.len) {
                if (std.mem.eql(u8, args[i + 1], "F")) {
                    use_fahrenheit = true;
                }
                i += 1;
            } else if (i == 1 && args.len >= 3 && !std.mem.eql(u8, args[1], "--unit")) {
                lat = args[1];
                lon = args[2];
                location_name = "specified coordinates";
                i += 2;
            } else {
                try stdout.print("Unknown argument: {s}. Use --help for usage.\n", .{args[i]});
                return;
            }
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

    if (request.response.status != .ok) {
        try stdout.print("API Error: Received status code {d}\n", .{ @intFromEnum(request.response.status) });
        return;
    }

    var response_body = std.ArrayList(u8).init(allocator);
    defer response_body.deinit();

    while (try request.read()) |chunk| {
        try response_body.appendSlice(chunk);
    }

    const body = response_body.items;
    
    if (std.mem.indexOf(u8, body, "\"current_weather\":") != null) {
        const temp_str = extractValue(body, "temperature");
        const wind = extractValue(body, "windspeed");
        const code = extractValue(body, "weathercode");
        const condition = getWeatherCondition(code);
        
        const timestamp = std.time.timestamp();
        const date = std.time.epoch_days(timestamp);
        const seconds_in_day = @as(i64, @intCast(timestamp % 86400));
        
        var year = 1970;
        var days_remaining = date;
        while (true) {
            const is_leap = (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0));
            const days_in_year: i64 = if (is_leap) 366 else 365;
            if (days_remaining < days_in_year) break;
            days_remaining -= days_in_year;
            year += 1;
        }

        const month_days = [_]i64{ 31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31 };
        var month: usize = 0;
        var days_in_month_remaining = days_remaining;
        while (month < 12) {
            var dim = month_days[month];
            if (month == 1 and (year % 4 == 0 and (year % 100 != 0 or year % 400 == 0))) dim += 1;
            if (days_in_month_remaining < dim) break;
            days_in_month_remaining -= dim;
            month += 1;
        }
        const day = days_in_month_remaining + 1;
        const hour = seconds_in_day / 3600;
        const minute = (seconds_in_day % 3600) / 60;
        const second = seconds_in_day % 60;

        var time_buf: [64]u8 = undefined;
        const time_str_fmt = try std.fmt.bufPrint(&time_buf, "{d}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} UTC", .{ year, month + 1, day, hour, minute, second });

        try stdout.print("\n┌──────────────────────────────────────┐\n", .{});
        try stdout.print("│          WEATHER REPORT               │\n", .{});
        try stdout.print("├──────────────────────────────────────┤\n", .{});
        try stdout.print("│ Location    : {s:<24} │\n", .{location_name});
        try stdout.print("│ Condition   : {s:<24} │\n", .{condition});
        
        var temp_display: [32]u8 = undefined;
        if (use_fahrenheit) {
            if (std.fmt.parseFloat(f32, temp_str)) |celsius| {
                const fahrenheit = (celsius * 9 / 5) + 32;
                _ = try std.fmt.bufPrint(&temp_display, "{d:.1} °F", .{fahrenheit});
            } else {
                _ = try std.fmt.bufPrint(&temp_display, "{s} °F (err)", .{temp_str});
            }
        } else {
            _ = try std.fmt.bufPrint(&temp_display, "{s} °C", .{temp_str});
        }
        
        try stdout.print("│ Temperature : {s:<24} │\n", .{temp_display});
        
        var wind_buf: [32]u8 = undefined;
        const wind_formatted = try std.fmt.bufPrint(&wind_buf, "{s} km/h", .{wind});
        try stdout.print("│ Windspeed   : {s:<24} │\n", .{wind_formatted});
        
        try stdout.print("│ Updated     : {s:<24} │\n", .{time_str_fmt});
        try stdout.print("└──────────────────────────────────────┘\n", .{});
    } else {
        try stdout.print("Failed to find weather data in response.\n", .{});
        try stdout.print("Response: {s}\n", .{body});
    }
}