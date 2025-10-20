DTB=./device_trees/kernel.dtb
RUN=qemu-system-arm -M virt -cpu cortex-a7 -nographic -m 512 -dtb $(DTB) -kernel zig-out/bin/kernel
DUMP_TO=dump.S

run:
	$(RUN)

drun:
	$(RUN) -s -S

flat_run:
	qemu-system-arm -M virt -cpu cortex-a7 -nographic -dtb $(DTB) -kernel zig-out/bin/kernel.bin

gdb:
	gdb-multiarch zig-out/bin/kernel -tui -x init.gdb

obj_dump:
	arm-linux-gnueabihf-objdump -d ./zig-out/bin/kernel > $(DUMP_TO)

objcopy:
	zig objcopy -O binary zig-out/bin/kernel zig-out/bin/kernel.bin

HEX_DUMP_FROM=
hexdump:
	hexdump -C $(HEX_DUMP_FROM)
