DTB=./device_trees/kernel.dtb
# RUN=qemu-system-arm -M virt -cpu cortex-a7 -nographic -m 512 -dtb $(DTB) -kernel zig-out/bin/kernel
RUN=qemu-system-arm -M virt,gic-version=2 -cpu cortex-a7 -nographic -m 512 -kernel zig-out/bin/kernel
DUMP_TO=dump.S

run:
	$(RUN)

drun:
	$(RUN) -s -S

gdb:
	gdb-multiarch zig-out/bin/kernel -tui -x init.gdb

obj_dump:
	arm-linux-gnueabihf-objdump -d ./zig-out/bin/kernel > $(DUMP_TO)

objcopy:
	zig objcopy -O binary zig-out/bin/kernel zig-out/bin/kernel.bin

HEX_DUMP_FROM=
hexdump:
	hexdump -C $(HEX_DUMP_FROM)
