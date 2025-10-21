pub fn Vxim(comptime Event: type, comptime WidgetId: type) type {
    return struct {
        const Self = @This();

        current_event: Event = undefined,
        mouse_focused_widget: ?WidgetId = null,

        _tty_buffer: []u8 = undefined,
        _tty: *vaxis.Tty,
        _vx: *vaxis.Vaxis,
        _loop: *vaxis.Loop(Event),

        pub const UpdateContext = struct {
            arena: std.mem.Allocator,
            root_win: vaxis.Window,
            vx: *vaxis.Vaxis,
            vxim: *Self,
            current_event: Event,
        };

        pub const UpdateResult = enum {
            keep_going,
            stop,
        };

        pub const TextOptions = struct {
            x: u16 = 0,
            y: u16 = 0,
            text: []const u8 = "",
            style: vaxis.Style = .{},
        };

        const ButtonAction = enum {
            clicked,
            hovered,
            none,
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

        const ButtonOptions = struct {
            x: u16 = 0,
            y: u16 = 0,
            text: []const u8 = "",
            style: Style.Button = .{},
        };

        pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
            self._loop.stop();

            // deinit takes an optional allocator. If your program is exiting, you can
            // choose to pass a null allocator to save some exit time.
            self._vx.deinit(gpa, self._tty.writer());

            self._tty.deinit();

            gpa.destroy(self._loop);
            gpa.destroy(self._vx);
            gpa.destroy(self._tty);
            gpa.free(self._tty_buffer);
        }

        pub fn init(gpa: std.mem.Allocator) Self {
            const buffer = gpa.alloc(u8, 1024) catch @panic("Failed to allocate memory for TTY buffer");
            const tty = gpa.create(vaxis.Tty) catch @panic("Failed to allocate memory for TTY");
            tty.* = vaxis.Tty.init(buffer) catch @panic("Failed to initialize TTY");

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
                ._tty_buffer = buffer,
                ._tty = tty,
                ._vx = vx,
                ._loop = loop,
            };
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
                        if (mouse.button == .left and mouse.type == .press) {
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

        pub fn text(_: *Self, win: vaxis.Window, opts: TextOptions) void {
            _ = win.printSegment(
                .{ .text = opts.text, .style = opts.style },
                .{ .col_offset = opts.x, .row_offset = opts.y, .wrap = .word },
            );
        }

        const WindowOptions = struct {
            x: u16 = 0,
            y: u16 = 0,
            width: u16 = 10,
            height: u16 = 10,
            title: []const u8 = "",
        };

        pub fn window(self: *Self, id: WidgetId, win: vaxis.Window, opts: WindowOptions) vaxis.Window {
            // 1. Get window.

            const window_widget = win.child(.{
                .x_off = opts.x,
                .y_off = opts.y,
                .width = opts.width,
                .height = opts.height,
            });
            window_widget.clear();

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

            const inner_window = window_widget.child(.{
                .x_off = 1,
                .y_off = 1,
                .width = window_widget.width -| 2,
                .height = window_widget.height -| 2,
            });

            // 3. Set focus.

            switch (self.current_event) {
                .mouse_focus => |mouse| {
                    if (window_widget.hasMouse(mouse)) |_| self.mouse_focused_widget = id;
                },
                .mouse => |mouse| {
                    if (window_widget.hasMouse(mouse)) |_| self._vx.setMouseShape(.default);
                },
                else => {},
            }

            // If we're not asking for a title, then just return the inside of the window.

            if (std.mem.eql(u8, opts.title, "")) return inner_window;

            // Otherwise, include the title bar.

            const title_bar = inner_window.child(.{ .height = 1 });

            self.text(title_bar, .{ .text = opts.title });

            const title_bar_separator = window_widget.child(.{ .y_off = 2, .height = 1 });
            title_bar_separator.fill(.{ .char = .{ .grapheme = "─" } });
            title_bar_separator.writeCell(0, 0, .{ .char = .{ .grapheme = "├" } });
            title_bar_separator.writeCell(
                window_widget.width -| 1,
                0,
                .{ .char = .{ .grapheme = "┤" } },
            );

            return inner_window.child(.{
                .y_off = 2,
                .height = inner_window.height -| 2,
            });
        }

        pub fn startLoop(
            self: *Self,
            gpa: std.mem.Allocator,
            updateFn: fn (ctx: UpdateContext) anyerror!UpdateResult,
        ) !void {
            try self._vx.enterAltScreen(self._tty.writer());
            try self._vx.queryTerminal(self._tty.writer(), 1 * std.time.ns_per_s);

            try self._vx.setMouseMode(self._tty.writer(), true);

            var arena_state: std.heap.ArenaAllocator = .init(gpa);
            defer arena_state.deinit();

            const arena = arena_state.allocator();

            main_loop: while (true) {
                self.current_event = self._loop.nextEvent();

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
                            .arena = arena,
                            .vx = self._vx,
                            .vxim = self,
                            .current_event = .{ .mouse_focus = mouse },
                        });

                        _ = arena_state.reset(.retain_capacity);

                        if (update_result == .stop) break :main_loop;

                        self.current_event = original_mouse_event;
                    },
                    else => {},
                }

                const update_result = try updateFn(.{
                    .root_win = win,
                    .arena = arena,
                    .vx = self._vx,
                    .vxim = self,
                    .current_event = self.current_event,
                });

                try self._vx.render(self._tty.writer());

                _ = arena_state.reset(.retain_capacity);

                if (update_result == .stop) break :main_loop;
            }
        }
    };
}

const std = @import("std");
const vaxis = @import("vaxis");
