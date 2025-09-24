RUN=qemu-system-arm -M virt -cpu cortex-a7 -nographic -kernel zig-out/bin/kernel
DUMP_TO=dump.S

run:
	$(RUN)

drun:
	$(RUN) -s -S

flat_run:
	qemu-system-arm -M virt -cpu cortex-a7 -nographic -kernel zig-out/bin/kernel.bin

gdb:
	gdb-multiarch zig-out/bin/kernel -x init.gdb

obj_dump:
	arm-linux-gnueabihf-objdump -d ./zig-out/bin/kernel > $(DUMP_TO)

objcopy:
	zig objcopy -O binary zig-out/bin/kernel zig-out/bin/kernel.bin
