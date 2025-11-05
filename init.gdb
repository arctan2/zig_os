target remote :1234
set trace-commands on
set logging file gdb.log
set logging on

define print_l1
	p/x *(unsigned int (*)[4096]) $arg0
end
