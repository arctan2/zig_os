target remote :1234
set logging file gdb.log
set logging on

define mmu_on
	echo Switching to higher half symbols...\n
	add-symbol-file /home/admin-u/stuff/os/zig/kernel/zig-out/bin/kernel 0xC0000000
end

define switch_symbol_table
	echo Switching to higher half symbols...\n
	add-symbol-file /home/admin-u/stuff/os/zig/kernel/zig-out/bin/kernel_gdb
end
