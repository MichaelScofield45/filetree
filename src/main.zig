const std = @import("std");
const rl = @import("c.zig");
const Entry = std.fs.Dir.Entry;
const ArenaAllocator = std.heap.ArenaAllocator;
const Allocator = std.mem.Allocator;

const SCREEN_WIDTH = 800;
const SCREEN_HEIGHT = 600;
const SPACING = 5;
var FONT_SIZE: f32 = 30;

const Node = struct {
    kind: enum { dir, file },
    depth: u32,
    open: bool = false,
    next: u32 = 0,
    name: [:0]const u8,

    fn openedBefore(self: Node, id: u32) bool {
        return self.next > id + 1;
    }

    pub fn format(self: Node, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        inline for (@typeInfo(Node).Struct.fields) |field| {
            switch (@typeInfo(field.type)) {
                .Pointer => try writer.print("{s} : {s}\n", .{ field.name, @field(self, field.name) }),
                .Optional => try writer.print("{s} : {?}\n", .{ field.name, @field(self, field.name) }),
                else => try writer.print("{s} : {}\n", .{ field.name, @field(self, field.name) }),
            }
        }
    }
};

const Button = struct {
    id: u32,
    rect: rl.Rectangle,

    fn checkCollision(self: Button, point: rl.Vector2) bool {
        return rl.CheckCollisionPointRec(point, self.rect);
    }
};

/// Thin wrapper around ArrayList to handle popping directories.
const PathList = struct {
    last_pop_pos: usize = 0,
    list: std.ArrayList(u8),

    fn init(allocator: std.mem.Allocator) PathList {
        return .{ .list = std.ArrayList(u8).init(allocator) };
    }

    fn deinit(self: *PathList) void {
        self.list.deinit();
    }

    fn getSlice(self: PathList) []const u8 {
        return self.list.items;
    }

    fn pop(self: *PathList) void {
        self.list.items.len = self.last_pop_pos;
    }

    inline fn len(self: PathList) usize {
        return self.list.items.len;
    }

    fn append(self: *PathList, str: []const u8) !void {
        // NOTE: this is offset by 1, but it should not underflow
        const prev_len = self.len() -| 1;
        try self.list.appendSlice(str);
        self.last_pop_pos = prev_len;
    }

    fn reset(self: *PathList) void {
        self.list.clearRetainingCapacity();
    }
};

pub fn main() !void {
    rl.InitWindow(SCREEN_WIDTH, SCREEN_HEIGHT, "filetree");
    rl.SetTargetFPS(60);

    var gpa_inst = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_inst.deinit();
    const gpa = gpa_inst.allocator();

    var arena_instance = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena_instance.deinit();
    const arena = arena_instance.allocator();

    var list = std.ArrayList(Node).init(gpa);
    defer list.deinit();

    var buttons = std.ArrayList(Button).init(gpa);
    defer buttons.deinit();

    var path = PathList.init(gpa);
    defer path.deinit();
    // first pass

    {
        var dir = try std.fs.cwd().openDir(".", .{ .iterate = true });
        defer dir.close();
        var it = dir.iterate();

        var scratch_arena_inst = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer scratch_arena_inst.deinit();
        const scratch_arena = scratch_arena_inst.allocator();

        var dir_list = std.ArrayList([:0]const u8).init(scratch_arena);
        var file_list = std.ArrayList([:0]const u8).init(scratch_arena);

        var count: usize = 0;
        while (try it.next()) |entry| : (count += 1) {
            const name_dup = try arena.dupeZ(u8, entry.name);
            switch (entry.kind) {
                .directory => try dir_list.append(name_dup),
                .file => try file_list.append(name_dup),
                else => std.log.err("filetype not handled", .{}),
            }
        }

        const total_size = dir_list.items.len + file_list.items.len;
        try list.ensureTotalCapacity(total_size);

        for (dir_list.items) |dir_item|
            list.appendAssumeCapacity(.{
                .kind = .dir,
                .name = dir_item,
                .depth = 1,
            });

        for (file_list.items) |file_item|
            list.appendAssumeCapacity(.{
                .kind = .file,
                .name = file_item,
                .depth = 1,
            });

        for (list.items, 0..) |*item, idx| {
            item.next = @intCast(idx + 1);
        }
    }

    var anchor = vec2(f32, 50, 50);
    while (!rl.WindowShouldClose()) {
        if (rl.IsKeyDown(rl.KEY_Q)) break;
        if (rl.IsKeyDown(rl.KEY_UP)) anchor.y += 10;
        if (rl.IsKeyDown(rl.KEY_DOWN)) anchor.y -= 10;
        if (rl.IsKeyDown(rl.KEY_LEFT)) anchor.x += 10;
        if (rl.IsKeyDown(rl.KEY_RIGHT)) anchor.x -= 10;
        if (rl.IsKeyPressed(rl.KEY_D)) debugPrint(list.items, path.getSlice());

        buttons.clearRetainingCapacity();
        try createButtons(&buttons, list.items, anchor.x, anchor.y);

        const mouse_pos = rl.GetMousePosition();

        // Clicking
        const mouse_left = rl.IsMouseButtonPressed(rl.MOUSE_BUTTON_LEFT);
        if (mouse_left) {
            path.reset();
            var prev_depth: u32 = 0;
            for (buttons.items) |button| {
                if (list.items[button.id].depth > prev_depth) {
                    // FIXME: messes up with populating dirs and the buttons
                    //     try path.append("/");
                    try path.append(list.items[button.id].name);
                    prev_depth = list.items[button.id].depth;
                } else {
                    path.pop();
                    try path.append(list.items[button.id].name);
                }

                // Button clicked
                if (button.checkCollision(mouse_pos)) {
                    const id = button.id;
                    std.log.info(
                        "id {}, name {s}, depth {}",
                        .{ id, list.items[id].name, list.items[id].depth },
                    );
                    list.items[id].open = !list.items[id].open;
                    if (list.items[id].open and !list.items[id].openedBefore(id))
                        try populateDir(gpa, arena, &list, path.getSlice(), id);
                }
            }
        }

        // Dragging
        if (rl.IsMouseButtonDown(rl.MOUSE_BUTTON_RIGHT)) {
            const mouse_delta = rl.GetMouseDelta();
            anchor.x += mouse_delta.x;
            anchor.y += mouse_delta.y;
        }

        // Scaling
        const wheel_scroll = rl.GetMouseWheelMove();
        if (wheel_scroll != 0.0) {
            if (rl.IsKeyDown(rl.KEY_LEFT_SHIFT))
                FONT_SIZE += wheel_scroll * 5
            else
                FONT_SIZE += wheel_scroll;

            if (FONT_SIZE < 0.0) FONT_SIZE = 0.0;
        }

        rl.ClearBackground(rl.RAYWHITE);

        rl.BeginDrawing();
        defer rl.EndDrawing();

        drawList(list.items, anchor);

        rl.DrawFPS(0, 0);
    }

    rl.CloseWindow();
}

inline fn createButtons(
    buttons: *std.ArrayList(Button),
    nodes: []const Node,
    _x: f32,
    _y: f32,
) !void {
    const x = _x;
    var y = _y;
    var curr_node: u32 = 0;
    while (curr_node < nodes.len) {
        if (nodes[curr_node].kind == .dir) {
            const curr_depth = nodes[curr_node].depth;
            try buttons.append(.{
                .id = curr_node,
                .rect = .{
                    .x = x + FONT_SIZE * @as(f32, @floatFromInt(curr_depth - 1)),
                    .y = y,
                    .width = FONT_SIZE,
                    .height = FONT_SIZE,
                },
            });
        }

        if (nodes[curr_node].open)
            curr_node += 1
        else
            curr_node = nodes[curr_node].next;

        y += FONT_SIZE + SPACING;
    }
}

inline fn drawList(nodes: []const Node, origin: rl.Vector2) void {
    if (nodes.len == 0) return;
    var curr_node: u32 = 0;
    const x: i32 = @intFromFloat(origin.x);
    var y: i32 = @intFromFloat(origin.y);
    while (curr_node < nodes.len) {
        const curr_depth: i32 = @intCast(nodes[curr_node].depth);
        switch (nodes[curr_node].kind) {
            .dir => {
                drawArrow(
                    @as(f32, @floatFromInt(x)) + FONT_SIZE * @as(f32, @floatFromInt(curr_depth - 1)),
                    @floatFromInt(y),
                    FONT_SIZE,
                    nodes[curr_node].open,
                );
                rl.DrawText(
                    nodes[curr_node].name,
                    @intCast(x + @as(i32, @intFromFloat(FONT_SIZE)) * curr_depth + SPACING * 2),
                    @intCast(y),
                    @intFromFloat(FONT_SIZE),
                    rl.DARKBLUE,
                );
                if (nodes[curr_node].open)
                    rl.DrawText(
                        "[open]",
                        @intCast(x + @as(i32, @intFromFloat(FONT_SIZE)) * curr_depth + 200),
                        @intCast(y),
                        @intFromFloat(FONT_SIZE),
                        rl.DARKBLUE,
                    );
            },
            .file => rl.DrawText(
                nodes[curr_node].name,
                @intCast(x + @as(i32, @intFromFloat(FONT_SIZE)) * (curr_depth - 1)),
                @intCast(y),
                @intFromFloat(FONT_SIZE),
                rl.BLACK,
            ),
        }
        y += @intFromFloat(FONT_SIZE + SPACING);
        if (!nodes[curr_node].open) {
            curr_node = nodes[curr_node].next;
            // std.debug.print("line 256\n", .{});
        } else {
            curr_node += 1;
            // std.debug.print("line 259\n", .{});
        }
        // curr_node += 1;
    }
}

fn populateDir(
    gpa: Allocator,
    arena: Allocator,
    list: *std.ArrayList(Node),
    path: []const u8,
    id: u32,
) !void {
    std.debug.print("path to open: {s}", .{path});
    const parent_dir_depth = if (list.items.len == 0) 0 else list.items[id].depth;

    var dir = try std.fs.cwd().openDir(path, .{ .iterate = true });
    defer dir.close();
    var it = dir.iterate();

    var scratch_arena_inst = std.heap.ArenaAllocator.init(gpa);
    defer scratch_arena_inst.deinit();
    const scratch_arena = scratch_arena_inst.allocator();

    var dir_list = std.ArrayList([:0]const u8).init(scratch_arena);
    var file_list = std.ArrayList([:0]const u8).init(scratch_arena);

    var count: usize = 0;
    while (try it.next()) |entry| : (count += 1) {
        const name_dup = try arena.dupeZ(u8, entry.name);
        switch (entry.kind) {
            .directory => try dir_list.append(name_dup),
            .file => try file_list.append(name_dup),
            else => std.log.err("filetype not handled", .{}),
        }
        std.debug.print("info: we got new items, total is now {}\n", .{count + 1});
    }

    const new_capacity = list.items.len + count;
    try list.ensureTotalCapacity(new_capacity);

    // Offset everything to the right
    for (list.items[id..]) |*item|
        item.next += @intCast(count);

    const after_id = id + 1;

    for (dir_list.items) |dir_item|
        list.insertAssumeCapacity(after_id, .{
            .kind = .dir,
            .name = dir_item,
            .depth = parent_dir_depth + 1,
        });

    for (file_list.items) |file_item|
        list.insertAssumeCapacity(after_id + dir_list.items.len, .{
            .kind = .file,
            .name = file_item,
            .depth = parent_dir_depth + 1,
        });

    for (list.items[after_id..][0..count], after_id..) |*item, idx| {
        if (idx == count)
            item.next = list.items[after_id].next;

        item.next = @intCast(idx + 1);
    }
}

inline fn vec2(comptime T: type, x: T, y: T) rl.Vector2 {
    return .{
        .x = x,
        .y = y,
    };
}

inline fn rect(x: i32, y: i32, w: i32, h: i32) rl.Rectangle {
    return .{
        .x = x,
        .y = y,
        .width = w,
        .height = h,
    };
}

inline fn drawArrow(x: f32, y: f32, size: f32, down: bool) void {
    const offset = size * 0.2;
    const r = rl.Rectangle{
        .x = x,
        .y = y,
        .width = size,
        .height = size,
    };
    rl.DrawRectangleRec(r, rl.BLACK);
    if (!down)
        rl.DrawTriangle(
            vec2(f32, x + offset, y + offset),
            vec2(f32, x + offset, y + size - offset),
            vec2(f32, x + size - offset, y + size / 2.0),
            rl.LIGHTGRAY,
        )
    else
        rl.DrawTriangle(
            vec2(f32, x + size - offset, y + offset),
            vec2(f32, x + offset, y + offset),
            vec2(f32, x + size / 2.0, y + size - offset),
            rl.LIGHTGRAY,
        );
}

inline fn drawArrowV(vec: rl.Vector2, size: i32, down: bool) rl.Rectangle {
    return drawArrow(vec.x, vec.y, size, down);
}

fn debugPrint(nodes: []const Node, path: []const u8) void {
    std.debug.print("current path variable: {s}\n", .{path});
    for (nodes) |node| {
        if (node.open) {
            for (0..node.depth - 1) |_| std.debug.print("-> ", .{});
            std.debug.print("{}\n", .{node});
        }
    }
}
