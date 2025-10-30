pub fn Vxim(comptime Event: type, comptime WidgetId: type) type {
    return struct {
        const Self = @This();

        current_event: Event = undefined,
        mouse_focused_widget: ?WidgetId = null,
        open_menu: ?WidgetId = null,
        last_mouse: ?vaxis.Mouse = null,

        widget_being_dragged: ?WidgetId = null,

        _tty_buffer: []u8 = undefined,
        _tty: *vaxis.Tty,
        _vx: *vaxis.Vaxis,
        _loop: *vaxis.Loop(Event),
        _arena_state: std.heap.ArenaAllocator,

        pub const UpdateContext = struct {
            root_win: vaxis.Window,
            vx: *vaxis.Vaxis,
            vxim: *Self,
            current_event: Event,
        };

        pub const UpdateResult = enum {
            keep_going,
            stop,
        };

        pub const Style = struct {
            pub const Button = struct {
                default: vaxis.Style = .{ .bg = .{ .index = 12 } },
                hovered: vaxis.Style = .{ .bg = .{ .index = 12 } },
                pressed: vaxis.Style = .{ .bg = .{ .index = 4 } },

                text: Text = .{
                    .default = .{ .fg = .{ .index = 12 }, .reverse = true },
                    .hovered = .{ .fg = .{ .index = 12 }, .reverse = true },
                    .pressed = .{ .fg = .{ .index = 4 }, .reverse = true },
                },
            };

            pub const Text = struct {
                default: vaxis.Style = .{},
                hovered: vaxis.Style = .{},
                pressed: vaxis.Style = .{},
            };
        };

        const ButtonAction = enum {
            clicked,
            hovered,
            none,
        };

        const ButtonOptions = struct {
            x: u16 = 0,
            y: u16 = 0,
            text: []const u8 = "",
            style: Style.Button = .{},
        };

        pub const TextOptions = struct {
            x: u16 = 0,
            y: u16 = 0,
            text: []const u8 = "",
            style: vaxis.Style = .{},
            allow_selection: bool = false,
        };

        const MenuItem = struct {
            name: []const u8,
            id: WidgetId,
        };

        const Menu = struct {
            name: []const u8,
            items: []const MenuItem,
            id: WidgetId,
        };

        const MenuBarAction = struct {
            id: WidgetId,
            action: ButtonAction,
        };

        const WindowOptions = struct {
            x: *u16,
            y: *u16,
            width: u16 = 10,
            height: u16 = 10,
            title: []const u8 = "",
        };

        const PaddingOpts = union(enum) {
            all: u16,
            hv: struct { horizontal: u16, vertical: u16 },
            each: struct { top: u16, right: u16, bottom: u16, left: u16 },
        };

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self._arena_state.deinit();

            self._loop.stop();
            self._vx.deinit(gpa, self._tty.writer());
            self._tty.deinit();

            gpa.destroy(self._loop);
            gpa.destroy(self._vx);
            gpa.destroy(self._tty);
            gpa.free(self._tty_buffer);
        }

        pub fn init(gpa: std.mem.Allocator) Self {
            const tty_buffer = gpa.alloc(u8, 1024) catch @panic("Failed to allocate memory for TTY buffer");
            const tty = gpa.create(vaxis.Tty) catch @panic("Failed to allocate memory for TTY");
            tty.* = vaxis.Tty.init(tty_buffer) catch @panic("Failed to initialize TTY");

            const vx = gpa.create(vaxis.Vaxis) catch @panic("Failed to allocate memory for vaxis");
            vx.* = vaxis.init(gpa, .{}) catch @panic("Failed to initialize vaxis");

            const loop = gpa.create(vaxis.Loop(Event)) catch @panic("Failed to allocate memory for event loop");
            loop.* = .{
                .tty = tty,
                .vaxis = vx,
            };
            loop.init() catch @panic("Failed to initialize event loop");
            loop.start() catch @panic("Failed to start event loop");

            return .{
                ._arena_state = .init(gpa),
                ._tty_buffer = tty_buffer,
                ._tty = tty,
                ._vx = vx,
                ._loop = loop,
            };
        }

        pub fn arena(self: *Self) std.mem.Allocator {
            return self._arena_state.allocator();
        }

        pub fn button(self: *Self, id: WidgetId, win: vaxis.Window, opts: ButtonOptions) ButtonAction {
            const button_widget = win.child(.{
                .x_off = opts.x,
                .y_off = opts.y,
                .width = @min(
                    @as(u16, @truncate(opts.text.len)) + 2,
                    win.width,
                ),
                .height = 1,
            });

            switch (self.current_event) {
                .mouse_focus => |mouse| {
                    if (button_widget.hasMouse(mouse)) |_| {
                        self.mouse_focused_widget = id;
                    }
                },
                .mouse => |mouse| {
                    if (button_widget.hasMouse(mouse)) |_| self._vx.setMouseShape(.pointer);
                },
                else => {},
            }

            const button_style = switch (self.current_event) {
                .mouse => |mouse| style: {
                    if (button_widget.hasMouse(mouse)) |_| {
                        if (self.mouse_focused_widget == id and mouse.button == .left and mouse.type == .press) {
                            break :style opts.style.pressed;
                        }

                        break :style opts.style.hovered;
                    }

                    break :style opts.style.default;
                },
                else => opts.style.default,
            };

            const text_style = switch (self.current_event) {
                .mouse => |mouse| style: {
                    if (button_widget.hasMouse(mouse)) |_| {
                        if (self.mouse_focused_widget == id and mouse.button == .left and mouse.type == .press) {
                            break :style opts.style.text.pressed;
                        }

                        break :style opts.style.text.hovered;
                    }

                    break :style opts.style.text.default;
                },
                else => opts.style.text.default,
            };

            button_widget.fill(.{ .style = button_style });

            _ = button_widget.printSegment(
                .{ .text = opts.text, .style = text_style },
                .{ .row_offset = 0, .col_offset = 1 },
            );

            // now decide the status to return.
            switch (self.current_event) {
                .mouse => |mouse| {
                    if (button_widget.hasMouse(mouse)) |_| {
                        if (self.mouse_focused_widget == id and mouse.button == .left and mouse.type == .press) {
                            return .clicked;
                        }

                        return .hovered;
                    }

                    return .none;
                },
                else => return .none,
            }
        }

        pub fn text(self: *Self, win: vaxis.Window, opts: TextOptions) void {
            _ = win.printSegment(
                .{ .text = opts.text, .style = opts.style },
                .{ .col_offset = opts.x, .row_offset = opts.y, .wrap = .word },
            );

            if (!opts.allow_selection) return;

            // If text can be selected we show the right mouse shape and allow selecting text.

            const result_box = win.child(.{
                .x_off = opts.x,
                .y_off = opts.y,
                .width = @truncate(opts.text.len),
                .height = 1,
            });

            switch (self.current_event) {
                .mouse => |mouse| {
                    if (result_box.hasMouse(mouse)) |_| self._vx.setMouseShape(.text);
                },
                else => {},
            }
        }

        pub fn padding(_: *Self, win: vaxis.Window, opts: PaddingOpts) vaxis.Window {
            switch (opts) {
                .all => |space| return win.child(.{
                    .x_off = space,
                    .y_off = space,
                    .width = win.width -| (2 * space),
                    .height = win.height -| (2 * space),
                }),
                .hv => |space| return win.child(.{
                    .x_off = space.horizontal,
                    .y_off = space.vertical,
                    .width = win.width -| (2 * space.horizontal),
                    .height = win.height -| (2 * space.vertical),
                }),
                .each => |space| return win.child(.{
                    .x_off = space.left,
                    .y_off = space.top,
                    .width = win.width -| space.left -| space.right,
                    .height = win.height -| space.top -| space.bottom,
                }),
            }
        }

        pub fn window(self: *Self, id: WidgetId, win: vaxis.Window, opts: WindowOptions) vaxis.Window {
            // 1. Get window.

            const window_widget = win.child(.{
                .x_off = opts.x.*,
                .y_off = opts.y.*,
                .width = opts.width,
                .height = opts.height,
            });
            window_widget.clear();

            // 2. Set focus.

            switch (self.current_event) {
                .mouse_focus => |mouse| {
                    if (window_widget.hasMouse(mouse)) |_| self.mouse_focused_widget = id;
                },
                .mouse => |mouse| {
                    if (window_widget.hasMouse(mouse)) |_| self._vx.setMouseShape(.default);
                },
                else => {},
            }

            const has_title = !std.mem.eql(u8, opts.title, "");

            const inner_window =
                window_widget.child(.{
                    .x_off = 1,
                    .y_off = 1,
                    .width = window_widget.width -| 2,
                    .height = window_widget.height -| 2,
                });

            // 2. Draw borders.

            const top_border = window_widget.child(.{
                .x_off = 1,
                .width = window_widget.width -| 2,
                .height = 1,
            });
            const right_border = window_widget.child(.{
                .x_off = window_widget.width -| 1,
                .y_off = 1,
                .width = 1,
                .height = window_widget.height -| 2,
            });
            const bottom_border = window_widget.child(.{
                .x_off = 1,
                .y_off = window_widget.height -| 1,
                .width = window_widget.width -| 2,
                .height = 1,
            });
            const left_border = window_widget.child(.{
                .y_off = 1,
                .width = 1,
                .height = window_widget.height -| 2,
            });

            top_border.fill(.{ .char = .{ .grapheme = "─" } });
            right_border.fill(.{ .char = .{ .grapheme = "│" } });
            bottom_border.fill(.{ .char = .{ .grapheme = "─" } });
            left_border.fill(.{ .char = .{ .grapheme = "│" } });

            window_widget.writeCell(0, 0, .{ .char = .{ .grapheme = "┌" } });
            window_widget.writeCell(window_widget.width -| 1, 0, .{ .char = .{ .grapheme = "┐" } });
            window_widget.writeCell(
                window_widget.width -| 1,
                window_widget.height -| 1,
                .{ .char = .{ .grapheme = "┘" } },
            );
            window_widget.writeCell(0, window_widget.height -| 1, .{ .char = .{ .grapheme = "└" } });

            if (!has_title) return inner_window;

            // Otherwise, include the title bar.

            const title_bar = window_widget.child(.{
                .x_off = 1,
                .width = window_widget.width -| 2,
                .height = 1,
            });

            self.text(title_bar, .{ .text = opts.title });

            // Drag handling

            if (self.mouse_focused_widget == id) switch (self.current_event) {
                .mouse_focus => |mouse| if (top_border.hasMouse(mouse)) |_| {
                    self.widget_being_dragged = id;
                },
                .mouse => |mouse| handle_drag: {
                    if (self.widget_being_dragged == id and mouse.button == .left and mouse.type == .drag) {
                        if (self.last_mouse) |last_mouse| {
                            if (mouse.col == last_mouse.col and mouse.row == last_mouse.row) break :handle_drag;

                            const is_moving_right = mouse.col > last_mouse.col;
                            const is_moving_down = mouse.row > last_mouse.row;

                            if (is_moving_right) opts.x.* +|= mouse.col - last_mouse.col;
                            if (!is_moving_right) opts.x.* -|= last_mouse.col - mouse.col;

                            if (is_moving_down) opts.y.* +|= mouse.row - last_mouse.row;
                            if (!is_moving_down) opts.y.* -|= last_mouse.row - mouse.row;
                        }
                    }

                    if (self.widget_being_dragged == id and mouse.button == .left and mouse.type == .release)
                        self.widget_being_dragged = null;
                },
                else => {},
            };

            return inner_window;
        }

        pub fn menuBar(self: *Self, win: vaxis.Window, menus: []const Menu) ?MenuBarAction {
            const menu_bar = win.child(.{ .height = 1 });

            var menu_button_offset: u16 = 0;

            var action: ?MenuBarAction = null;

            for (menus) |menu| {
                const menu_width = widest_item_width: {
                    var width: usize = 0;
                    for (menu.items) |item| width = @max(width, item.name.len + 2);

                    break :widest_item_width width;
                };

                const menu_button = self.button(menu.id, menu_bar, .{
                    .x = menu_button_offset,
                    .text = menu.name,
                });

                const menu_area = win.child(.{
                    .x_off = menu_button_offset,
                    .y_off = 1,
                    .width = @min(menu_width, win.width),
                    .height = @min(menu.items.len, win.height),
                });

                // Draw the drop-down menu, if one is open.

                if (self.open_menu == menu.id) {
                    for (menu.items, 0..) |item, idx| {
                        const button_text_writer_buf = self.arena().alloc(u8, menu_width) catch
                            @panic("failed to allocate for aligning menu items");
                        var button_text_writer: std.Io.Writer = .fixed(button_text_writer_buf);

                        // Make sure button covers the entire menu and make the text left aligned.

                        button_text_writer.alignBuffer(item.name, menu_width, .left, ' ') catch
                            @panic("failed to center menu item");
                        const button_text = button_text_writer.buffered();

                        const button_action = self.button(
                            item.id,
                            menu_area,
                            .{ .y = @truncate(idx), .text = button_text },
                        );

                        // If the button is clicked, we close the menu.
                        if (button_action == .clicked) self.open_menu = null;
                        // If any interaction is done with the button we use that as the return
                        // value for this function to communicate which menu was interacted with.
                        if (button_action != .none)
                            action = .{ .id = item.id, .action = button_action };
                    }

                    // Close the drop-down menu if you left-click outside it.

                    switch (self.current_event) {
                        .mouse => |mouse| if (mouse.button == .left and mouse.type == .press) {
                            if (menu_button != .clicked and menu_area.hasMouse(mouse) == null)
                                self.open_menu = null;
                        },
                        else => {},
                    }
                }

                const should_toggle_menu = menu_button == .clicked;

                if (should_toggle_menu) {
                    self.open_menu = if (self.open_menu == menu.id) null else menu.id;
                }

                menu_button_offset +|= @as(u16, @truncate(menu.name.len)) + 2;
            }

            return action;
        }

        pub fn startLoop(
            self: *Self,
            gpa: std.mem.Allocator,
            updateFn: fn (ctx: UpdateContext) anyerror!UpdateResult,
        ) !void {
            try self._vx.enterAltScreen(self._tty.writer());
            try self._vx.queryTerminal(self._tty.writer(), 1 * std.time.ns_per_s);

            try self._vx.setMouseMode(self._tty.writer(), true);

            main_loop: while (true) {
                defer _ = self._arena_state.reset(.retain_capacity);

                self.current_event = self._loop.nextEvent();

                self._vx.setMouseShape(.default);

                const win = self._vx.window();

                switch (self.current_event) {
                    .winsize => |ws| try self._vx.resize(gpa, self._tty.writer(), ws),
                    .mouse => |mouse| if (mouse.type == .press and @hasField(Event, "mouse_focus")) {

                        // Builtin widgets read directly from self.current_event so we have to make
                        // sure that's set correctly. It's not sufficient to just pass a different
                        // event to the `updateFn`.
                        const original_mouse_event = self.current_event;
                        self.current_event = .{ .mouse_focus = mouse };

                        const update_result = try updateFn(.{
                            .root_win = win,
                            .vx = self._vx,
                            .vxim = self,
                            .current_event = .{ .mouse_focus = mouse },
                        });

                        _ = self._arena_state.reset(.retain_capacity);

                        if (update_result == .stop) break :main_loop;

                        self.current_event = original_mouse_event;
                    },
                    else => {},
                }

                const update_result = try updateFn(.{
                    .root_win = win,
                    .vx = self._vx,
                    .vxim = self,
                    .current_event = self.current_event,
                });

                switch (self.current_event) {
                    .mouse => |mouse| self.last_mouse = mouse,
                    else => {},
                }

                // Debug info
                if (builtin.mode == .Debug) {
                    const last_cursor_text = try std.fmt.allocPrint(self.arena(), "Last cursor: ({d},{d})", .{
                        if (self.last_mouse) |m| m.col else 0,
                        if (self.last_mouse) |m| m.row else 0,
                    });
                    const focused_widget_text = try std.fmt.allocPrint(
                        self.arena(),
                        "Focused widget: {?}",
                        .{self.mouse_focused_widget},
                    );
                    const widget_being_dragged_text = try std.fmt.allocPrint(
                        self.arena(),
                        "Dragging: {?}",
                        .{self.widget_being_dragged},
                    );

                    const widest_text = @max(last_cursor_text.len, focused_widget_text.len, widget_being_dragged_text.len);

                    const dbg_win = win.child(.{
                        .x_off = win.width -| 2 -| @as(u16, @truncate(widest_text)),
                        .y_off = 1,
                        .width = @as(u16, @truncate(widest_text)) +| 2,
                        .height = 5,
                        .border = .{ .where = .all },
                    });

                    self.text(dbg_win, .{
                        .x = dbg_win.width -| @as(u16, @truncate(last_cursor_text.len)),
                        .y = 0,
                        .text = last_cursor_text,
                    });
                    self.text(dbg_win, .{
                        .x = dbg_win.width -| @as(u16, @truncate(focused_widget_text.len)),
                        .y = 1,
                        .text = focused_widget_text,
                    });
                    self.text(dbg_win, .{
                        .x = dbg_win.width -| @as(u16, @truncate(widget_being_dragged_text.len)),
                        .y = 2,
                        .text = widget_being_dragged_text,
                    });

                    self.text(win, .{
                        .x = @as(u16, @intCast(dbg_win.x_off)),
                        .y = @as(u16, @intCast(dbg_win.y_off)) -| 1,
                        .text = "Debug Info",
                    });
                }

                try self._vx.render(self._tty.writer());

                if (update_result == .stop) break :main_loop;
            }
        }
    };
}

const std = @import("std");
const builtin = @import("builtin");
const vaxis = @import("vaxis");
