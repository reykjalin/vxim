const ButtonAction = enum {
    pressed,
    released,
    hovered,
    none,
};

const ButtonOptions = struct {
    x: u16,
    y: u16,
    text: []const u8,
    mouse: ?vaxis.Mouse,
};

pub fn button(win: vaxis.Window, opts: ButtonOptions) ButtonAction {
    const child = win.child(.{
        .x_off = opts.x,
        .y_off = opts.y,
        .width = @as(u16, @truncate(opts.text.len)) + 2,
        .height = 1,
    });

    const button_has_mouse = child.hasMouse(opts.mouse) != null;
    const button_pressed = if (opts.mouse) |mouse| button_has_mouse and mouse.button == .left and mouse.type == .press else false;

    if (button_pressed) {
        child.fill(.{ .style = .{ .bg = .{ .index = 9 } } });
    } else if (button_has_mouse) {
        child.fill(.{ .style = .{ .bg = .{ .index = 8 }, .reverse = true } });
    } else {
        child.fill(.{ .style = .{ .bg = .{ .index = 8 } } });
    }

    const text_style_idx: u8 = if (button_has_mouse and button_pressed) 9 else 8;

    _ = child.printSegment(
        .{ .text = opts.text, .style = .{ .bg = .{ .index = text_style_idx }, .reverse = button_has_mouse and !button_pressed } },
        .{ .row_offset = 0, .col_offset = 1 },
    );

    const button_released = if (opts.mouse) |mouse| button_has_mouse and mouse.button == .left and mouse.type == .release else false;

    if (button_pressed) return .pressed;
    if (button_released) return .released;
    if (button_has_mouse) return .hovered;
    return .none;
}

const TextOptions = struct {
    x: u16 = 0,
    y: u16 = 0,
    text: []const u8 = "",
    style: vaxis.Style = .{},
};

pub fn text(win: vaxis.Window, opts: TextOptions) void {
    _ = win.printSegment(
        .{ .text = opts.text, .style = opts.style },
        .{ .col_offset = opts.x, .row_offset = opts.y },
    );
}

const vaxis = @import("vaxis");
