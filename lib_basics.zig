pub const lib = struct {
    pub const Bss = struct {
        pub fn prepare() void {
            @memset(@ptrCast([*]u8, &__bss_start), 0, @ptrToInt(&__bss_end) - @ptrToInt(&__bss_start));
        }
    };

    const Gpiote = struct {
        const p = peripheral(6);
        pub const tasks = struct {
            pub const out = p.taskArray(4, 0x000);
        };
        pub const events = struct {
            pub const in = p.eventArray(4, 0x100);
            pub const port = p.event(0x17c);
        };
        pub const registers = struct {
            pub const shorts = p.shorts(0x200);
            pub const interrupts = p.RegisterWriteSetClear(0x300, 0x304, 0x308);
            pub const config = p.mmioxArray(4, 0x510, packed struct {
                mode: enum(u2) {
                    Disabled,
                    Event,
                    Task = 3,
                } = .Disabled,
                unused1: u6 = 0,
                psel: u5 = 0,
                unused2: u3 = 0,
                polarity: enum(u2) {
                    None,
                    LoToHi,
                    HiToLo,
                    Toggle,
                } = .None,
                unused3: u2 = 0,
                outinit: enum(u1) {
                    Low,
                    High,
                } = .Low,
                unused4: u11 = 0,
            });
        };
    };

    const Adc = struct {
        const p = peripheral(7);
        pub const tasks = struct {
            pub const start = p.task(0x000);
            pub const stop = p.task(0x004);
        };
        pub const events = struct {
            pub const end = p.event(0x100);
        };
        pub const registers = struct {
            pub const shorts = p.shorts(0x200);
            pub const interrupts = p.registerSetClear(0x304, 0x308);
            pub const busy = p.register(0x400);
            pub const enable = p.register(0x500);
            pub const config = p.mmiox(0x504, packed struct {
                resolution: u2 = 0,
                inpsel: u3 = 0,
                refsel: u2 = 0,
                unused1: u1 = 0,
                psel: u8 = 0,
                extrefsel: u2 = 0,
                unused2: u14 = 0,
            });
            pub const result = p.register(0x508);
        };
    };

    const ClockManagement = struct {
        const p = peripheral(0);
        pub const tasks = struct {
            pub const start_hf_clock = p.task(0x000);
            pub const stop_hf_clock = p.task(0x004);
            pub const start_lf_clock = p.task(0x008);
            pub const stop_lf_clock = p.task(0x00c);
        };
        pub const events = struct {
            pub const hf_clock_started = p.event(0x100);
            pub const lf_clock_started = p.event(0x104);
        };
        pub const registers = struct {
            pub const shorts = p.shorts(0x200);
            pub const interrupts = p.RegisterWriteSetClear(0x300, 0x304, 0x308);
            pub const frequency_selector = p.register(0x550);
        };
        pub fn prepareHf() void {
            registers.frequency_selector.write(0xff);
            tasks.start_hf_clock.do();
            while (!events.hf_clock_started.occurred()) {}
        }
    };

    pub const Exceptions = struct {
        var already_panicking: bool = undefined;
        var panic_handler: ?fn (message: []const u8, trace: ?*builtin.StackTrace) noreturn = undefined;
        pub fn handle(exception_number: u32) noreturn {
            panicf("exception number {} ... now idle in arm exception handler", .{exception_number});
        }
        pub fn prepare() void {
            already_panicking = false;
            panic_handler = null;
        }
        pub fn setPanicHandler(new_panic_handler: ?fn (message: []const u8, trace: ?*builtin.StackTrace) noreturn) void {
            panic_handler = new_panic_handler;
        }
    };

    pub const Ficr = struct {
        pub fn deviceId() u64 {
            return @as(u64, contents[0x64 / 4]) << 32 | contents[0x60 / 4];
        }
        pub fn dump() void {
            for (contents) |word, i| {
                log("{x:2} {x:8}", .{ i * 4, word });
            }
        }
        pub fn isQemu() bool {
            return deviceId() == 0x1234567800000003;
        }
        pub const contents = @intToPtr(*[64]u32, 0x10000000);
        pub const radio = @intToPtr(*extern struct {
            device_address_type: u32,
            device_address0: u32,
            device_address1: u32,
        }, 0x100000a0);
    };

    const Gpio = struct {
        const p = peripheral(0x10000);
        pub const registers = struct {
            pub const out = p.registerWriteSetClear(0x504, 0x508, 0x50c);
            pub const in = p.register(0x510);
            pub const direction = p.registerWriteSetClear(0x514, 0x518, 0x51c);
            pub const config = p.mmioxArray(32, 0x700, packed struct {
                output_connected: u1,
                input_disconnected: u1,
                pull: enum(u2) { disabled, down, up = 3 },
                unused1: u4 = 0,
                drive: enum(u3) { s0s1, h0s1, s0h1, h0h1, d0s1, d0h1, s0d1, h0d1 },
                unused2: u5 = 0,
                sense: enum(u2) { disabled, high = 2, low },
                unused3: u14 = 0,
            });
        };
    };

    pub const Pins = struct {
        pub const ring0 = ioPin(3);
        pub const ring1 = ioPin(2);
        pub const ring2 = ioPin(1);
        pub const leds = struct {
            pub const cathodes = ioPinField(4, 9, 0x1ff0);
            pub const anodes = ioPinField(13, 3, 0xe000);
            pub const mask = anodes.mask | cathodes.mask;
        };
        pub const i2c = struct {
            pub const scl = oPin(0);
            pub const sda = ioPin(30);
        };
        pub const buttons = struct {
            pub const a = iPin(17);
            pub const b = iPin(26);
        };
        pub const uart = struct {
            pub const tx = oPin(24);
            pub const rx = iPin(25);
        };
        fn iPin(id: u32) type {
            return pin(id);
        }
        fn ioPin(id: u32) type {
            return pin(id);
        }
        fn pin(the_id: u32) type {
            return struct {
                pub const id = the_id;
                pub const mask = 1 << id;
                pub const direction = struct {
                    pub fn set() void {
                        Gpio.registers.direction.set(mask);
                    }
                };
                pub fn clear() void {
                    Gpio.registers.out.clear(mask);
                }
                pub fn connectInput() void {
                    Gpio.registers.config[id].write(.{ .output_connected = 0, .input_disconnected = 0, .pull = .disabled, .drive = .s0s1, .sense = .disabled });
                }
                pub fn connectIo() void {
                    Gpio.registers.config[id].write(.{ .output_connected = 1, .input_disconnected = 0, .pull = .disabled, .drive = .s0s1, .sense = .disabled });
                }
                pub fn connectOutput() void {
                    Gpio.registers.config[id].write(.{ .output_connected = 1, .input_disconnected = 1, .pull = .disabled, .drive = .s0s1, .sense = .disabled });
                }
                pub fn read() u32 {
                    return (Gpio.registers.in.read() & mask) >> id;
                }
                pub fn set() void {
                    Gpio.registers.out.set(mask);
                }
            };
        }
        fn oPin(id: u32) type {
            return pin(id);
        }
        fn iPinField(id: u32, width: u32) type {
            return pinField(id, width);
        }
        fn ioPinField(id: u32, width: u32, mask: u32) type {
            return pinField(id, width, mask);
        }
        fn pinField(the_id: u32, the_width: u32, the_mask: u32) type {
            return struct {
                pub const id = the_id;
                pub const mask = the_mask;
                pub const width = the_width;
                pub const direction = struct {
                    pub fn setAll() void {
                        Gpio.registers.direction.set(mask);
                    }
                };
                pub fn clearAll() void {
                    Gpio.registers.out.clear(mask);
                }
                pub fn connectAllInput() void {
                    var i: u32 = id;
                    while (i < id + width) : (i += 1) {
                        Gpio.registers.config.write(id, .{ .output_connected = 0, .input_disconnected = 0, .pull = .disabled, .drive = .s0s1, .sense = .disabled });
                    }
                }
                pub fn connectAllIo() void {
                    var i: u32 = id;
                    while (i < id + width) : (i += 1) {
                        Gpio.registers.config.write(id, .{ .output_connected = 1, .input_disconnected = 0, .pull = .disabled, .drive = .s0s1, .sense = .disabled });
                    }
                }
                pub fn connectAllOutput() void {
                    var i: u32 = id;
                    while (i < id + width) : (i += 1) {
                        Gpio.registers.config.write(id, .{ .output_connected = 1, .input_disconnected = 1, .pull = .disabled, .drive = .s0s1, .sense = .disabled });
                    }
                }
                pub fn read() u32 {
                    return (Gpio.registers.in.read() & mask) >> id;
                }
                pub fn setAll() void {
                    Gpio.registers.out.set(mask);
                }
            };
        }
        fn oPinField(id: u32, width: u32) type {
            return pinField(id, width);
        }
    };

    pub const led_anode_number_and_cathode_number_indexed_by_y_then_x = [5][5][2]u32{
        .{ .{ 1, 1 }, .{ 2, 4 }, .{ 1, 2 }, .{ 2, 5 }, .{ 1, 3 } },
        .{ .{ 3, 4 }, .{ 3, 5 }, .{ 3, 6 }, .{ 3, 7 }, .{ 3, 8 } },
        .{ .{ 2, 2 }, .{ 1, 9 }, .{ 2, 3 }, .{ 3, 9 }, .{ 2, 1 } },
        .{ .{ 1, 8 }, .{ 1, 7 }, .{ 1, 6 }, .{ 1, 5 }, .{ 1, 4 } },
        .{ .{ 3, 3 }, .{ 2, 7 }, .{ 3, 1 }, .{ 2, 6 }, .{ 3, 2 } },
    };

    fn I2c(comptime instance_id: u32) type {
        assert(instance_id < 2);
        return struct {
            const p = peripheral(3 + instance_id);
            pub const tasks = struct {
                pub const startrx = p.task(0x000);
                pub const starttx = p.task(0x008);
                pub const stop = p.task(0x014);
                pub const suspend_task = p.task(0x01c);
                pub const resume_task = p.task(0x020);
            };
            pub const events = struct {
                pub const stopped = p.event(0x104);
                pub const rxready = p.event(0x108);
                pub const txdsent = p.event(0x11c);
                pub const error_event = p.event(0x124);
                pub const byte_break = p.event(0x138);
            };
            pub const registers = struct {
                pub const shorts = p.shorts(0x200);
                pub const interrupts = p.RegisterWriteSetClear(0x300, 0x304, 0x308);
                pub const errorsrc = p.mmiox(0x4c4, packed struct {
                    overrun: u1,
                    address_nack: u1,
                    data_nack: u1,
                    unused1: u29,
                });
                pub const enable = p.register(0x500);
                pub const pselscl = p.register(0x508);
                pub const pselsda = p.register(0x50c);
                pub const rxd = p.register(0x518);
                pub const txd = p.register(0x51c);
                pub const frequency = p.mmiox(0x524, enum(u32) {
                    K100 = 0x01980000,
                    K250 = 0x04000000,
                    K400 = 0x06680000,
                });
                pub const device_address = p.register(0x588);
            };
            pub fn prepare() void {
                registers.enable.write(0);
                Pins.i2c.scl.direction.set();
                Pins.i2c.sda.direction.set();
                registers.pselscl.write(Pins.i2c.scl.id);
                registers.pselscl.write(Pins.i2c.sda.id);
                registers.frequency.write(.K400);
                registers.enable.write(5);
            }
            pub fn probe(device_address: u32) !void {
                registers.device_address.write(device_address);
                tasks.startrx.do();
                defer tasks.stop.do();
                try wait(events.byte_break);
            }
            pub fn readBlocking(device_address: u32, data: []u8, first: u32, last: u32) !void {
                registers.device_address.write(device_address);
                tasks.starttx.do();
                registers.txd.write(first);
                try waitForEvent(events.txdsent);
                tasks.startrx.do();
                var i = first;
                while (i <= last) : (i += 1) {
                    if (i == last) {
                        tasks.stop.do();
                    }
                    try waitForEvent(events.rxready);
                    data[i] = @truncate(u8, registers.rxd.read());
                }
            }
            pub fn readBlockingPanic(device_address: u32, data: []u8, first: u32, last: u32) void {
                if (readBlocking(device_address, data, first, last)) |_| {} else |err| {
                    panicf("i2c device 0x{x} read {} errorsrc 0x{x}", .{ device_address, err, registers.errorsrc });
                }
            }
            pub fn waitForEvent(comptime the_event: Event) !void {
                const start = Timer(0).captureAndRead();
                while (true) {
                    if (the_event.occurred()) {
                        the_event.clear();
                        return;
                    }
                    if (@bitCast(u32, registers.errorsrc.read()) != 0) {
                        return error.I2cErrorSourceRegister;
                    }
                    if (Timer(0).captureAndRead() -% start > 500 * 1000) {
                        return error.I2cTimeExpired;
                    }
                }
            }
            pub fn writeByteBlocking(device_address: u32, data: []u8, first: u32, last: u32) !void {
                registers.device_address.write(device_address);
                tasks.starttx.do();
                registers.txd.write(first);
                try waitForEvent(events.txdsent);
                var i = first;
                while (i <= last) : (i += 1) {
                    registers.txd.write(data[i]);
                    try waitForEvent(events.txdsent);
                }
                tasks.stop.do();
            }
            pub fn writeBlockingPanic(device_address: u32, data: []u8, first: u32, last: u32) void {
                if (writeByteBlocking(device_address, data, first, last)) |_| {} else |err| {
                    panicf("i2c device 0x{x} write {} errorsrc 0x{x}", .{ device_address, err, registers.errorsrc });
                }
            }
        };
    }

    pub const LedMatrix = struct {
        var scan_lines: [3]u9 = undefined;
        var scan_lines_index: u32 = undefined;
        pub var image: u32 = undefined;
        pub var scan_timer: TimeKeeper = undefined;
        pub fn clear() void {
            for (scan_lines) |*scan_line| {
                scan_line.* = 0;
            }
        }
        pub fn prepare() void {
            image = 0;
            Gpio.registers.direction.set(Pins.leds.mask);
            clear();
            scan_lines_index = 0;
            putChar('Z');
            scan_timer.prepare(3 * 1000);
        }
        pub fn putChar(byte: u8) void {
            putImage(getImage(byte));
        }
        pub fn putImage(new_image: u32) void {
            image = new_image;
            clear();
            var mask: u32 = 0x1;
            var y: i32 = 4;
            while (y >= 0) : (y -= 1) {
                var x: i32 = 4;
                while (x >= 0) : (x -= 1) {
                    if (image & mask != 0) {
                        putPixel(@intCast(u32, x), @intCast(u32, y), 1);
                    }
                    mask <<= 1;
                }
            }
        }
        fn putPixel(x: u32, y: u32, v: u32) void {
            const anode_number_and_cathode_number = led_anode_number_and_cathode_number_indexed_by_y_then_x[y][x];
            const selected_scan_line_index = anode_number_and_cathode_number[0] - 1;
            const col_mask = @as(u9, 1) << @truncate(u4, anode_number_and_cathode_number[1] - 1);
            scan_lines[selected_scan_line_index] = scan_lines[selected_scan_line_index] & ~col_mask | if (v == 0) 0 else col_mask;
        }
        pub fn update() void {
            if (scan_timer.isFinishedThenReset()) {
                Gpio.registers.out.clear(Pins.leds.mask);
                Gpio.registers.out.set((@as(u32, 1) << @truncate(u5, 13 + scan_lines_index)) | (@as(u32, ~scan_lines[scan_lines_index]) << 4));
                scan_lines_index = (scan_lines_index + 1) % scan_lines.len;
            }
        }
        pub fn getImage(byte: u8) u32 {
            return switch (byte) {
                ' ' => 0b0000000000000000000000000,
                '0' => 0b1111110001100011000111111,
                '1' => 0b0010001100001000010001110,
                '2' => 0b1111100001111111000011111,
                '3' => 0b1111100001001110000111111,
                '4' => 0b1000110001111110000100001,
                '5' => 0b1111110000111110000111111,
                '6' => 0b1111110000111111000111111,
                '7' => 0b1111100001000100010001000,
                '8' => 0b1111110001111111000111111,
                '9' => 0b1111110001111110000100001,
                'A' => 0b0111010001111111000110001,
                'B' => 0b1111010001111111000111110,
                'Z' => 0b1111100010001000100011111,
                else => 0b0000000000001000000000000,
            };
        }
    };

    const Ppi = struct {
        const p = peripheral(31);
        pub const tasks = struct {
            pub const group0_enable = p.task(0x000);
            pub const group0_disable = p.task(0x004);
            pub const group1_enable = p.task(0x008);
            pub const group1_disable = p.task(0x00c);
            pub const group2_enable = p.task(0x010);
            pub const group2_disable = p.task(0x014);
            pub const group3_enable = p.task(0x018);
            pub const group3_disable = p.task(0x01c);
        };
        pub const interrupts = p.interrupts(.None);
        pub const registers = struct {
            pub const shorts = p.shorts(0x200);
            pub const event_end_points = p.registerArrayDelta(16, 0x510, 8);
            pub const task_end_points = p.registerArrayDelta(16, 0x514, 8);
            pub const channel_enable = p.registerWriteSetClear(0x500, 0x504, 0x508);
        };
        pub fn setChannelEventAndTask(comptime channel: u32, event: Event, task: Task) void {
            registers.event_end_points[channel].write(@ptrToInt(event.address));
            registers.task_end_points[channel].write(@ptrToInt(task.address));
        }
    };

    const Power = struct {
        const p = peripheral(0);
        pub const registers = struct {
            pub const shorts = p.shorts(0x200);
            pub const interrupts = p.RegisterWriteSetClear(0x300, 0x304, 0x308);
            pub const reset_reason = p.register(0x400);
        };
        pub var captured_reset_reason: u32 = undefined;
        pub fn captureResetReason() void {
            captured_reset_reason = registers.reset_reason.read();
            registers.reset_reason.write(captured_reset_reason);
        }
    };

    const Radio = struct {
        const p = peripheral(1);
        pub const tasks = struct {
            pub const tx_enable = p.task(0x000);
            pub const rx_enable = p.task(0x004);
            pub const start = p.task(0x008);
            pub const stop = p.task(0x00c);
            pub const disable = p.task(0x010);
        };
        pub const events = struct {
            pub const ready = p.event(0x100);
            pub const address_completed = p.event(0x104);
            pub const payload_completed = p.event(0x108);
            pub const packed_completed = p.event(0x10c);
            pub const disabled = p.event(0x110);
        };
        pub const registers = struct {
            pub const shorts = p.register(0x200);
            pub const interrupts = p.registerSetClear(0x304, 0x308);
            pub const crc_status = p.register(0x400);
            pub const rx_crc = p.register(0x40c);
            pub const packet_ptr = p.register(0x504);
            pub const frequency = p.register(0x508);
            pub const tx_power = p.register(0x50c);
            pub const mode = p.register(0x510);
            pub const pcnf0 = p.register(0x514);
            pub const pcnf1 = p.register(0x518);
            pub const base0 = p.register(0x51c);
            pub const base1 = p.register(0x520);
            pub const prefix0 = p.register(0x524);
            pub const prefix1 = p.register(0x528);
            pub const tx_address = p.register(0x52c);
            pub const rx_addresses = p.register(0x530);
            pub const crc_config = p.register(0x534);
            pub const crc_poly = p.register(0x538);
            pub const crc_init = p.register(0x53c);
            pub const state = p.register(0x550);
            pub const datawhiteiv = p.register(0x554);
        };
    };

    const Rng = struct {
        const p = peripheral(13);
        pub const tasks = struct {
            pub const start = p.task(0x000);
            pub const stop = p.task(0x004);
        };
        pub const events = struct {
            pub const value_ready = p.event(0x100);
        };
        pub const registers = struct {
            pub const shorts = p.shorts(0x200);
            pub const interrupts = p.RegisterWriteSetClear(0x300, 0x304, 0x308);
            pub const config = p.mmio(0x504, packed struct {
                enable: u1 = 0,
                unused1: u31 = 0,
            });
            pub const value = p.register(0x508);
        };
    };

    pub const SystemControlBlock = struct {
        const p = peripheral(0xa000e);
        pub const registers = struct {
            pub const cpuid = p.register(0xd00);
            pub const icsr = p.register(0xd04);
            pub const aircr = p.register(0xd0c);
            pub const scr = p.register(0xd10);
            pub const ccr = p.register(0xd14);
            pub const shpr2 = p.register(0xd1c);
            pub const shpr3 = p.register(0xd20);
        };
        pub fn requestSystemReset() void {
            registers.aircr.write(0x05fa0004);
        }
    };

    const Temperature = struct {
        const p = peripheral(12);
        pub const tasks = struct {
            pub const start = p.task(0x000);
            pub const stop = p.task(0x004);
        };
        pub const events = struct {
            pub const data_ready = p.event(0x100);
        };
        pub const registers = struct {
            pub const shorts = p.shorts(0x200);
            pub const interrupts = p.RegisterWriteSetClear(0x300, 0x304, 0x308);
            pub const temperature = p.register(0x508);
        };
    };

    const Wdt = struct {
        const p = peripheral(16);
        pub const tasks = struct {
            pub const start = p.task(0x000);
        };
        pub const events = struct {
            pub const timeout = p.event(0x100);
        };
        pub const registers = struct {
            pub const shorts = p.shorts(0x200);
            pub const interrupts = p.registerSetClear(0x304, 0x308);
            pub const run_status = p.register(0x400);
            pub const request_status = p.register(0x404);
            pub const counter_reset_value = p.register(0x504);
            pub const reload_request_enable = p.register(0x508);
            pub const config = p.register(0x50c);
            pub const reload_request = p.registerArray(8, 0x600);
        };
    };

    fn peripheral(comptime peripheral_id: u32) type {
        return struct {
            const base = 0x40000000 + peripheral_id * 0x1000;
            fn event(comptime offset: u32) Event {
                var e: Event = undefined;
                e.address = @intToPtr(*align(4) volatile u32, base + offset);
                return e;
            }
            fn mmiox(comptime offset: u32, comptime layout: type) type {
                return struct {
                    pub noinline fn read() layout {
                        return @ptrCast(*align(4) volatile layout, address).*;
                    }
                    pub noinline fn write(x: layout) void {
                        @ptrCast(*align(4) volatile layout, address).* = x;
                    }
                    pub const address = @intToPtr(*align(4) volatile u32, base + offset);
                };
            }
            fn register(comptime offset: u32) type {
                return mmiox(offset, u32);
            }
            fn registerWriteSetClear(comptime write_offset: u32, comptime set_offset: u32, comptime clear_offset: u32) type {
                return struct {
                    pub fn read() u32 {
                        return register(write_offset).read();
                    }
                    pub fn write(x: u32) void {
                        register(write_offset).write(x);
                    }
                    pub fn set(x: u32) void {
                        register(set_offset).write(x);
                    }
                    pub fn clear(x: u32) void {
                        register(clear_offset).write(x);
                    }
                };
            }
            fn Register(comptime T: type) type {
                return struct {
                    address: *align(4) volatile u32,
                    pub noinline fn read(self: @This()) T {
                        return @ptrCast(*align(4) volatile T, self.address).*;
                    }
                    pub noinline fn write(self: @This(), x: T) void {
                        @ptrCast(*align(4) volatile T, self.address).* = x;
                    }
                };
            }
            fn mmioxArray(comptime length: u32, comptime offset: u32, comptime T: type) [length]Register(T) {
                return addressedArray(length, offset, 4, Register(T));
            }
            fn registerArray(comptime length: u32, comptime offset: u32) [length]Register(u32) {
                return addressedArray(length, offset, 4, Register(u32));
            }
            fn registerArrayDelta(comptime length: u32, comptime offset: u32, comptime delta: u32) [length]Register(u32) {
                return addressedArray(length, offset, delta, Register(u32));
            }
            fn shorts(comptime EventsType: type, comptime TasksType: type, event2: EventsType.enums, task2: TasksType.enums) type {
                return struct {
                    fn enable(pairs: []struct { event: EventsType.enums, task: TasksType.enums }) void {}
                };
            }
            fn task(comptime offset: u32) Task {
                var t: Task = undefined;
                t.address = @intToPtr(*align(4) volatile u32, base + offset);
                return t;
            }
            fn addressedArray(comptime length: u32, comptime offset: u32, comptime delta: u32, comptime T: type) [length]T {
                var t: [length]T = undefined;
                var i: u32 = 0;
                while (i < length) : (i += 1) {
                    t[i].address = @intToPtr(*align(4) volatile u32, base + offset + i * delta);
                }
                return t;
            }
            fn eventArray(comptime length: u32, comptime offset: u32) [length]Event {
                return addressedArray(length, offset, 4, Event);
            }
            fn taskArray(comptime length: u32, comptime offset: u32) [length]Task {
                return addressedArray(length, offset, 4, Task);
            }
        };
    }

    const Event = struct {
        address: *align(4) volatile u32,
        pub fn clear(self: Event) void {
            self.address.* = 0;
        }
        pub fn occurred(self: Event) bool {
            return self.address.* == 1;
        }
    };

    const Task = struct {
        address: *align(4) volatile u32,
        pub fn do(self: Task) void {
            self.address.* = 1;
        }
    };

    pub const Terminal = struct {
        var height: u32 = 24;
        var width: u32 = 80;

        pub fn attribute(n: u32) void {
            pair(n, 0, "m");
        }

        pub fn clearScreen() void {
            pair(2, 0, "J");
        }

        pub fn hideCursor() void {
            Uart.writeText(csi ++ "?25l");
        }

        pub fn line(comptime fmt: []const u8, args: var) void {
            format(fmt, args);
            pair(0, 0, "K");
            Uart.writeText("\n");
        }

        pub fn move(row: u32, column: u32) void {
            pair(row, column, "H");
        }

        pub fn pair(a: u32, b: u32, letter: []const u8) void {
            if (a <= 1 and b <= 1) {
                format("{}{}", .{ csi, letter });
            } else if (b <= 1) {
                format("{}{}{}", .{ csi, a, letter });
            } else if (a <= 1) {
                format("{};{}{}", .{ csi, b, letter });
            } else {
                format("{}{};{}{}", .{ csi, a, b, letter });
            }
        }

        pub fn requestCursorPosition() void {
            Uart.writeText(csi ++ "6n");
        }

        pub fn requestDeviceCode() void {
            Uart.writeText(csi ++ "c");
        }

        pub fn reset() void {
            Uart.writeText("\x1bc");
        }

        pub fn restoreCursorAndAttributes() void {
            Uart.writeText("\x1b8");
        }

        pub fn saveCursorAndAttributes() void {
            Uart.writeText("\x1b7");
        }

        pub fn setLineWrap(enabled: bool) void {
            pair(0, 0, if (enabled) "7h" else "7l");
        }

        pub fn setScrollingRegion(top: u32, bottom: u32) void {
            pair(top, bottom, "r");
        }

        pub fn showCursor() void {
            Uart.writeText(csi ++ "?25h");
        }

        const csi = "\x1b[";
    };

    pub const TimeKeeper = struct {
        duration: u32,
        max_elapsed: u32,
        start_time: u32,

        fn capture(self: *TimeKeeper) u32 {
            Timer(0).tasks.capture[0].do();
            return Timer(0).registers.capture_compare[0].read();
        }

        fn elapsed(self: *TimeKeeper) u32 {
            return self.capture() -% self.start_time;
        }

        fn prepare(self: *TimeKeeper, duration: u32) void {
            self.duration = duration;
            self.max_elapsed = 0;
            self.reset();
        }

        fn isFinishedThenReset(self: *TimeKeeper) bool {
            const since = self.elapsed();
            if (since >= self.duration) {
                if (since > self.max_elapsed) {
                    self.max_elapsed = since;
                }
                self.reset();
                return true;
            } else {
                return false;
            }
        }

        fn reset(self: *TimeKeeper) void {
            self.start_time = self.capture();
        }

        fn wait(self: *TimeKeeper) void {
            while (!self.isFinishedThenReset()) {}
        }

        pub fn delay(duration: u32) void {
            var time_keeper: TimeKeeper = undefined;
            time_keeper.prepare(duration);
            time_keeper.wait();
        }
    };

    // bit mode
    // prescaler
    fn Timer(instance_id: u32) type {
        assert(instance_id < 3);
        return struct {
            const max_width = if (instance_id == 0) @as(u32, 32) else 16;
            const p = peripheral(8 + instance_id);
            pub const tasks = struct {
                pub const start = p.task(0x000);
                pub const stop = p.task(0x004);
                pub const count = p.task(0x008);
                pub const clear = p.task(0x00c);
                pub const capture = p.taskArray(4, 0x040);
            };
            pub const events = struct {
                pub const compare = p.eventArray(4, 0x140);
            };
            pub const registers = struct {
                pub const shorts = p.register(0x200);
                pub const interrupts = p.registerSetClear(0x304, 0x308);
                pub const mode = p.register(0x504);
                pub const bit_mode = p.register(0x508);
                pub const prescaler = p.register(0x510);
                pub const capture_compare = p.registerArray(4, 0x540);
            };
            pub fn captureAndRead() u32 {
                tasks.capture[0].do();
                return registers.capture_compare[0].read();
            }
            pub fn prepare() void {
                registers.mode.write(0x0);
                registers.bit_mode.write(if (instance_id == 0) @as(u32, 0x3) else 0x0);
                registers.prescaler.write(if (instance_id == 0) @as(u32, 4) else 9);
                tasks.start.do();
                const now = captureAndRead();
                var i: u32 = 0;
                while (captureAndRead() == now) : (i += 1) {
                    if (i == 1000) {
                        panicf("timer {} is not responding", .{instance_id});
                    }
                }
            }
        };
    }

    const Uart = struct {
        const p = peripheral(2);
        pub const tasks = struct {
            pub const start_rx = p.task(0x000);
            pub const stop_rx = p.task(0x004);
            pub const start_tx = p.task(0x008);
            pub const stop_tx = p.task(0x00c);
        };
        pub const events = struct {
            pub const cts = p.event(0x100);
            pub const not_cts = p.event(0x104);
            pub const rx_ready = p.event(0x108);
            pub const tx_ready = p.event(0x11c);
            pub const error_detected = p.event(0x124);
            pub const rx_timeout = p.event(0x144);
        };
        pub const registers = struct {
            pub const shorts = p.shorts(0x200);
            pub const interrupts = p.RegisterWriteSetClear(0x300, 0x304, 0x308);
            pub const error_source = p.register(0x480);
            pub const enable = p.register(0x500);
            pub const pin_select_rts = p.register(0x508);
            pub const pin_select_txd = p.register(0x50c);
            pub const pin_select_cts = p.register(0x510);
            pub const pin_select_rxd = p.register(0x514);
            pub const rxd = p.register(0x518);
            pub const txd = p.register(0x51c);
            pub const baud_rate = p.register(0x524);
        };
        var stream: std.io.OutStream(Uart, stream_error, writeTextError) = undefined;
        var tx_busy: bool = undefined;
        var tx_queue: [3]u8 = undefined;
        var tx_queue_read: usize = undefined;
        var tx_queue_write: usize = undefined;
        var updater: ?fn () void = undefined;
        const stream_error = error{UartError};
        pub fn drainTxQueue() void {
            while (tx_queue_read != tx_queue_write) {
                loadTxd();
            }
        }
        pub fn prepare() void {
            Pins.uart.tx.connectOutput();
            registers.pin_select_rxd.write(Pins.uart.rx.id);
            registers.pin_select_txd.write(Pins.uart.tx.id);
            registers.enable.write(0x04);
            tasks.start_rx.do();
            tasks.start_tx.do();
        }
        pub fn isReadByteReady() bool {
            return events.rx_ready.occurred();
        }
        pub fn format(comptime fmt: []const u8, args: var) void {
            std.fmt.format(stream, fmt, args) catch |_| {};
        }
        pub fn loadTxd() void {
            if (tx_queue_read != tx_queue_write and (!tx_busy or events.tx_ready.occurred())) {
                events.tx_ready.clear();
                registers.txd.write(tx_queue[tx_queue_read]);
                tx_queue_read = (tx_queue_read + 1) % tx_queue.len;
                tx_busy = true;
                if (updater) |an_updater| {
                    an_updater();
                }
            }
        }
        pub fn log(comptime fmt: []const u8, args: var) void {
            format(fmt ++ "\n", args);
        }
        pub fn writeText(buffer: []const u8) void {
            for (buffer) |c| {
                switch (c) {
                    '\n' => {
                        writeByteBlocking('\r');
                        writeByteBlocking('\n');
                    },
                    else => writeByteBlocking(c),
                }
            }
        }
        pub fn writeTextError(self: Uart, buffer: []const u8) stream_error!usize {
            writeText(buffer);
            return buffer.len;
        }
        pub fn setUpdater(new_updater: fn () void) void {
            updater = new_updater;
        }
        pub fn update() void {
            loadTxd();
        }
        pub fn writeByteBlocking(byte: u8) void {
            const next = (tx_queue_write + 1) % tx_queue.len;
            while (next == tx_queue_read) {
                loadTxd();
            }
            tx_queue[tx_queue_write] = byte;
            tx_queue_write = next;
            loadTxd();
        }
        pub fn readByte() u8 {
            events.rx_ready.clear();
            return @truncate(u8, registers.rxd.read());
        }
    };

    pub const Uicr = struct {
        pub const contents = @intToPtr(*[64]u32, 0x10001000);
        pub fn dump() void {
            for (contents) |word, i| {
                log("{x:2} {x:8}", .{ i * 4, word });
            }
        }
    };

    pub fn hangf(comptime fmt: []const u8, args: var) noreturn {
        log(fmt, args);
        Uart.drainTxQueue();
        while (true) {}
    }

    pub fn panic(message: []const u8, trace: ?*builtin.StackTrace) noreturn {
        if (Exceptions.panic_handler) |handler| {
            handler(message, trace);
        } else {
            panicf("panic(): {}", .{message});
        }
        while (true) {}
    }

    pub fn panicf(comptime fmt: []const u8, args: var) noreturn {
        @setCold(true);
        if (Exceptions.already_panicking) {
            hangf("\npanicked during panic", .{});
        }
        Exceptions.already_panicking = true;
        log("\npanicf(): " ++ fmt, args);
        var it = std.debug.StackIterator.init(null, null);
        while (it.next()) |stacked_address| {
            dumpReturnAddress(stacked_address - 1);
        }
        hangf("panic completed", .{});
    }

    fn dumpReturnAddress(return_address: usize) void {
        var symbol_index: usize = 0;
        var line: []const u8 = "";
        var i: u32 = 0;
        while (i < symbols.len) {
            var j: u32 = i;
            while (symbols[j] != '\n') {
                j += 1;
            }
            const next_line = symbols[i..j];
            const symbol_address = std.fmt.parseUnsigned(usize, next_line[0..8], 16) catch 0;
            if (symbol_address >= return_address) {
                break;
            }
            line = next_line;
            i = j + 1;
        }
        if (line.len >= 3) {
            log("{x:5} in {}", .{ return_address, line[3..] });
        } else {
            log("{x:5}", .{return_address});
        }
    }

    fn exception() callconv(.C) noreturn {
        const ipsr_interrupt_program_status_register = asm ("mrs %[ipsr_interrupt_program_status_register], ipsr"
            : [ipsr_interrupt_program_status_register] "=r" (-> usize)
        );
        const isr_number = ipsr_interrupt_program_status_register & 0xff;
        panicf("exception {}", .{isr_number});
    }

    pub fn simpleVectorTable(main: fn () callconv(.C) noreturn) [1 + 15 + model.number_of_peripherals]fn () callconv(.C) noreturn {
        return .{
            model.initial_sp, main,      exception, exception, exception, exception, exception, exception,
            exception,        exception, exception, exception, exception, exception, exception, exception,
            exception,        exception, exception, exception, exception, exception, exception, exception,
            exception,        exception, exception, exception, exception, exception, exception, exception,
            exception,        exception, exception, exception, exception, exception, exception, exception,
            exception,        exception, exception, exception, exception, exception, exception, exception,
        };
    }

    const assert = std.debug.assert;
    const builtin = std.builtin;
    const format = Uart.format;
    const model = @import("build.zig").model;
    const std = @import("std");
    const symbols = @embedFile("symbols.txt");

    extern var __bss_start: u8;
    extern var __bss_end: u8;
    extern var __debug_info_start: u8;
    extern var __debug_info_end: u8;
    extern var __debug_abbrev_start: u8;
    extern var __debug_abbrev_end: u8;
    extern var __debug_str_start: u8;
    extern var __debug_str_end: u8;
    extern var __debug_line_start: u8;
    extern var __debug_line_end: u8;
    extern var __debug_ranges_start: u8;
    extern var __debug_ranges_end: u8;

    pub const log = Uart.log;
    pub const ram_u32 = @intToPtr(*align(4) volatile [4096]u32, 0x20000000);
};

pub const typical = struct {
    pub const Adc = lib.Adc;
    pub const assert = lib.assert;
    pub const Bss = lib.Bss;
    pub const builtin = std.builtin;
    pub const ClockManagement = lib.ClockManagement;
    pub const Exceptions = lib.Exceptions;
    pub const Ficr = lib.Ficr;
    pub const format = Uart.format;
    pub const Gpio = lib.Gpio;
    pub const Gpio2 = lib.Gpio2;
    pub const Gpiote = lib.Gpiote;
    pub const I2c = lib.I2c;
    pub const lib_basics = lib;
    pub const log = Uart.log;
    pub const math = std.math;
    pub const mem = std.mem;
    pub const LedMatrix = lib.LedMatrix;
    pub const panic = lib.panic;
    pub const panicf = lib.panicf;
    pub const Pins = lib.Pins;
    pub const Power = lib.Power;
    pub const Ppi = lib.Ppi;
    pub const simpleVectorTable = lib.simpleVectorTable;
    pub const std = @import("std");
    pub const SystemControlBlock = lib.SystemControlBlock;
    pub const Temperature = lib.Temperature;
    pub const Terminal = lib.Terminal;
    pub const TimeKeeper = lib.TimeKeeper;
    pub const Timer = lib.Timer;
    pub const linkVectorTable = lib.linkVectorTable;
    pub const Uart = lib.Uart;
    pub const Uicr = lib.Uicr;
    pub const Wdt = lib.Wdt;
};

export fn __sync_lock_test_and_set_4(ptr: *u32, val: u32) callconv(.C) u32 {
    // disable the IRQ
    const old_val = ptr.*;
    ptr.* = val;
    // enable the IRQ
    return old_val;
}
