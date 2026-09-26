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

/// Maps degrees to compass direction
fn getWindDirection(degrees_str: []const u8) []const u8 {
    if (std.fmt.parseFloat(f32, degrees_str)) |deg| {
        const dirs = [_][]const u8{ "N", "NE", "E", "SE", "S", "SW", "W", "NW", "N" };
        const idx = @as(usize, @intCast((deg + 22.5) / 45.0));
        if (idx < dirs.len) return dirs[idx];
    }
    return "Unknown";
}

/// Robust helper to extract value by key from simple JSON
fn extractValue(body: []const u8, key: []const u8) []const u8 {
    var search_key_buf: [64]u8 = undefined;
    const search_key = std.fmt.bufPrint(&search_key_buf, "\"{s}\":", .{key}) catch return "";

    const idx = std.mem.indexOf(u8, body, search_key) orelse return "";
    var val_start = idx + search_key.len;

    // Skip whitespace and colons
    while (val_start < body.len and (body[val_start] == ' ' or body[val_start] == '\t' or body[val_start] == '\n' or body[val_start] == '\r' or body[val_start] == ':')) {
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
    // Trim trailing spaces
    while (result.len > 0 and (result[result.len - 1] == ' ' or result[result.len - 1] == '\t')) {
        result = result[0..result.len - 1];
    }
    // Trim quotes for string values
    if (result.len >= 2 and result[0] == '"' and result[result.len - 1] == '"') {
        result = result[1..result.len - 1];
    }
    return result;
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
    var city_name: ?[]const u8 = null;

    if (args.len > 1) {
        if (std.mem.eql(u8, args[1], "--help") or std.mem.eql(u8, args[1], "-h")) {
            try stdout.print("Usage: z-weather-cli [options]\n\nOptions:\n  --city <name>       Fetch weather for a city name\n  --lat <lat> <lon>    Specify latitude and longitude\n  --unit <C|F>         Temperature unit (C for Celsius, F for Fahrenheit)\n  --help, -h           Show this help message\n\nExample:\n  z-weather-cli --city "New York"
  z-weather-cli --lat 40.71 -74.00 --unit F\n", .{});
            return;
        }

        var i: usize = 1;
        while (i < args.len) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, arg, "--city")) {
                if (i + 1 < args.len) {
                    city_name = args[i + 1];
                    i += 1;
                } else {
                    try stdout.print("Error: --city requires a city name.\n", .{});
                    return;
                }
            } else if (std.mem.eql(u8, arg, "--lat")) {
                if (i + 2 < args.len) {
                    lat = args[i + 1];
                    lon = args[i + 2];
                    location_name = "specified coordinates";
                    i += 2;
                } else {
                    try stdout.print("Error: --lat requires both latitude and longitude.\n", .{});
                    return;
                }
            } else if (std.mem.eql(u8, arg, "--unit")) {
                if (i + 1 < args.len) {
                    if (std.mem.eql(u8, args[i + 1], "F")) {
                        use_fahrenheit = true;
                    }
                    i += 1;
                } else {
                    try stdout.print("Error: --unit requires a value (C or F).\n", .{});
                    return;
                }
            } else if (i == 1 && args.len >= 3 && !std.mem.eql(u8, arg, "--unit") and !std.mem.eql(u8, arg, "--city")) {
                // Positional arguments for lat/lon
                lat = args[1];
                lon = args[2];
                location_name = "specified coordinates";
                i += 2;
            } else {
                try stdout.print("Unknown argument: {s}. Use --help for usage.\n", .{arg});
                return;
            }
        }
    }

    if (city_name) |city| {
        const geo_url = try std.fmt.allocPrint(allocator, "https://geocoding-api.open-meteo.com/v1/search?name={s}&count=1&language=en&format=json", .{city});
        defer allocator.free(geo_url);

        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        var server_header_buffer: [1024]u8 = undefined;
        const request = client.open(.GET, geo_url, .{ .response_headers_buffer = &server_header_buffer }) catch |err| {
            try stdout.print("Network Error: Geocoding failed. {any}\n", .{err});
            return;
        };
        defer request.deinit();

        request.headers.append("User-Agent", "z-weather-cli/1.0 (Zig CLI utility)") catch {};
        request.send() catch |err| {
            try stdout.print("Network Error: Failed to send geocoding request. {any}\n", .{err});
            return;
        };
        request.wait() catch |err| {
            try stdout.print("Network Error: Failed to wait for geocoding response. {any}\n", .{err});
            return;
        };

        var geo_body = std.ArrayList(u8).init(allocator);
        defer geo_body.deinit();
        while (try request.read()) |chunk| {
            try geo_body.appendSlice(chunk);
        }

        const res_body = geo_body.items;
        if (std.mem.indexOf(u8, res_body, "\"results\":") == null) {
            try stdout.print("Error: City '{s}' not found.\n", .{city});
            return;
        }

        const found_lat = extractValue(res_body, "latitude");
        const found_lon = extractValue(res_body, "longitude");
        const found_name = extractValue(res_body, "name");

        if (found_lat.len == 0 or found_lon.len == 0) {
            try stdout.print("Error: Could not extract coordinates for {s}.\n", .{city});
            return;
        }

        lat = try allocator.dupe(u8, found_lat);
        lon = try allocator.dupe(u8, found_lon);
        location_name = try allocator.dupe(u8, found_name);
    }

    // Basic coordinate validation
    if (std.fmt.parseFloat(f32, lat)) |lat_val| {
        if (lat_val < -90 or lat_val > 90) {
            try stdout.print("Error: Latitude must be between -90 and 90.\n", .{});
            return;
        }
    } else {
        try stdout.print("Error: Invalid latitude format: {s}\n", .{lat});
        return;
    }
    if (std.fmt.parseFloat(f32, lon)) |lon_val| {
        if (lon_val < -180 or lon_val > 180) {
            try stdout.print("Error: Longitude must be between -180 and 180.\n", .{});
            return;
        }
    } else {
        try stdout.print("Error: Invalid longitude format: {s}\n", .{lon});
        return;
    }

    // Cache logic
    var cache_path_buf: [128]u8 = undefined;
    const cache_path = try std.fmt.bufPrint(&cache_path_buf, ".weather_cache_{s}_{s}", .{ lat, lon });
    
    var body: []const u8 = "";
    var from_cache = false;

    const cached_file = std.fs.cwd().openFile(cache_path, .{}, null) catch null;
    if (cached_file) |file| {
        defer file.close();
        const stat = file.stat() catch null;
        if (stat) |s| {
            const mtime = s.mtime orelse 0;
            const now = std.time.timestamp();
            if (now - mtime < 1800) { // 30 minutes cache
                const size = @intCast(s.size);
                const buf = try allocator.alloc(u8, size);
                _ = try file.readAll(buf);
                body = buf;
                from_cache = true;
            }
        }
    }

    if (!from_cache) {
        const url = try std.fmt.allocPrint(allocator, "https://api.open-meteo.com/v1/forecast?latitude={s}&longitude={s}&current_weather=true&current=relative_humidity_2m,apparent_temperature", .{ lat, lon });
        defer allocator.free(url);

        try stdout.print("Fetching current weather for {s} ({s}, {s})...\n", .{ location_name, lat, lon });

        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        var server_header_buffer: [1024]u8 = undefined;
        
        const request = client.open(.GET, url, .{ .response_headers_buffer = &server_header_buffer }) catch |err| {
            try stdout.print("Network Error: Could not open connection. {any}\n", .{err});
            return;
        };
        defer request.deinit();

        // Set a User-Agent as requested by Open-Meteo
        request.headers.append("User-Agent", "z-weather-cli/1.0 (Zig CLI utility)") catch {};

        request.send() catch |err| {
            try stdout.print("Network Error: Failed to send request. {any}\n", .{err});
            return;
        };
        request.wait() catch |err| {
            try stdout.print("Network Error: Failed to wait for response. {any}\n", .{err});
            return;
        };

        if (request.response.status != .ok) {
            try stdout.print("API Error: Received status code {d}\n", .{ @intFromEnum(request.response.status) });
            return;
        }

        var response_body = std.ArrayList(u8).init(allocator);
        defer response_body.deinit();

        while (try request.read()) |chunk| {
            try response_body.appendSlice(chunk);
        }

        body = try allocator.dupe(u8, response_body.items);
        
        // Save to cache
        const cache_file = std.fs.cwd().createFile(cache_path, .{}) catch null;
        if (cache_file) |f| {
            defer f.close();
            _ = f.writeAll(body) catch {};
        }
    } else {
        try stdout.print("Using cached data for {s} ({s}, {s})...\n", .{ location_name, lat, lon });
    }

    defer allocator.free(body);

    if (std.mem.indexOf(u8, body, "\"current_weather\":") != null) {
        const temp_str = extractValue(body, "temperature");
        const wind = extractValue(body, "windspeed");
        const wind_dir_str = extractValue(body, "winddirection");
        const code = extractValue(body, "weathercode");
        const condition = getWeatherCondition(code);
        
        const humidity = extractValue(body, "relative_humidity_2m");
        const apparent_temp_str = extractValue(body, "apparent_temperature");

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

        var apparent_display: [32]u8 = undefined;
        if (use_fahrenheit) {
            if (std.fmt.parseFloat(f32, apparent_temp_str)) |celsius| {
                const fahrenheit = (celsius * 9 / 5) + 32;
                _ = try std.fmt.bufPrint(&apparent_display, "{d:.1} °F", .{fahrenheit});
            } else {
                _ = try std.fmt.bufPrint(&apparent_display, "{s} °F (err)", .{apparent_temp_str});
            }
        } else {
            _ = try std.fmt.bufPrint(&apparent_display, "{s} °C", .{apparent_temp_str});
        }
        
        var wind_buf: [32]u8 = undefined;
        const wind_dir = getWindDirection(wind_dir_str);
        const wind_formatted = try std.fmt.bufPrint(&wind_buf, "{s} km/h ({s})", .{wind, wind_dir});

        var humid_buf: [32]u8 = undefined;
        const humid_formatted = try std.fmt.bufPrint(&humid_buf, "{s}%", .{humidity});

        // Calculate dynamic width
        var max_val_len = location_name.len;
        if (condition.len > max_val_len) max_val_len = condition.len;
        if (temp_display.len > max_val_len) max_val_len = temp_display.len;
        if (wind_formatted.len > max_val_len) max_val_len = wind_formatted.len;
        if (time_str_fmt.len > max_val_len) max_val_len = time_str_fmt.len;
        if (humid_formatted.len > max_val_len) max_val_len = humid_formatted.len;
        if (apparent_display.len > max_val_len) max_val_len = apparent_display.len;
        
        const inner_width = if (max_val_len < 24) 24 else max_val_len;
        
        try stdout.print("\n┌", .{});
        for (0..inner_width + 2) |_| try stdout.print("─", .{});
        try stdout.print("┐\n", .{});
        
        try stdout.print("│", .{});
        const header_text = "WEATHER REPORT";
        const total_width = inner_width + 2;
        const left_padding = (total_width - header_text.len) / 2;
        const right_padding = total_width - header_text.len - left_padding;
        
        for (0..left_padding) |_| try stdout.print(" ", .{});
        try stdout.print("{s}", .{header_text});
        for (0..right_padding) |_| try stdout.print(" ", .{});
        try stdout.print("│\n", .{});

        try stdout.print("├", .{});
        for (0..inner_width + 2) |_| try stdout.print("─", .{});
        try stdout.print("┤\n", .{});

        try stdout.print("│ Location    : {s:<{d}} │\n", .{ location_name, inner_width });
        
        try stdout.print("├", .{});
        for (0..inner_width + 2) |_| try stdout.print("─", .{});
        try stdout.print("┤\n", .{});

        try stdout.print("│ Condition   : {s:<{d}} │\n", .{ condition, inner_width });
        try stdout.print("│ Temperature : {s:<{d}} │\n", .{ temp_display, inner_width });
        try stdout.print("│ Feels Like  : {s:<{d}} │\n", .{ apparent_display, inner_width });
        try stdout.print("│ Humidity    : {s:<{d}} │\n", .{ humid_formatted, inner_width });
        try stdout.print("│ Windspeed   : {s:<{d}} │\n", .{ wind_formatted, inner_width });
        try stdout.print("│ Updated     : {s:<{d}} │\n", .{ time_str_fmt, inner_width });
        
        try stdout.print("└", .{});
        for (0..inner_width + 2) |_| try stdout.print("─", .{});
        try stdout.print("┘\n", .{});
    } else {
        try stdout.print("Failed to find weather data in response.\n", .{});
        try stdout.print("Response: {s}\n", .{body});
    }
}