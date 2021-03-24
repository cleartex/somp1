source [find mem_helper.tcl]

proc prep_prog {} {
	load_image boot_mp1.out
	arm core_state arm
	# inform bootloader to run flash programming
	mww 0x2ffc252c 1
	resume 0x2ffc2538
	wait_halt 4000
}

proc run_boot {name} {
	load_image $name.out
	arm core_state arm
	resume 0x2ffc2538
}

proc call_ldr {addr src sz} {
	mww 0x2ffc2520 $addr
	mww 0x2ffc2524 $src
	mww 0x2ffc2528 $sz
	resume 0x2ffc2534
}

proc prog_spi {fn tgt mode} {
	prep_prog
	set rsz [load_image $fn 0xc0000000]
	scan $rsz %d sz
	echo [format "Loaded %d bytes" $sz]
	call_ldr $tgt 0xc0000000 $sz
	wait_halt 30000
}

proc scan_bb {} {
	prep_prog
	call_ldr 0 1 0
}

proc dump_bbt {eb} {
	prep_prog
	call_ldr $eb 5 0
}

proc make_bb {pg} {
	prep_prog
	call_ldr $pg 4 0
}

proc dump_pg {pg} {
	prep_prog
	call_ldr $pg 2 0
}

# uses pagenumber as input!
proc erase_eb {pg} {
	prep_prog
	call_ldr $pg 3 0
}

proc prog_lin {} {
	prog_spi uImage 0x100000 0
}

proc prog_dtboot {} {
	prog_spi boot_mp1.stm32 0 0
}

proc prog_dtb {n} {
	prog_spi $n.dtu 0x40000 0
}
proc prog_dtb2 {n} {
	prog_spi $n.dtu 0x80000 0
}

proc prog_157 {} {
	if {[read_otp 9]==0} then {
		echo "Write OTP 9"
		write_otp 9 0xA0420000
	}
	prog_dtboot
	prog_dtb lump1-portn
	prog_dtb2 lump1-tester-u7
	prog_lin
	setbf 0x15 0x41 0
	run_boot boot_mp1
}
proc prog_151 {} {
	if {[read_otp 9]==0} then {
		echo "Write OTP 9"
		write_otp 9 0x80220000
	}
	prog_dtboot
	prog_dtb lump1-portn
	prog_dtb2 lump1-tester-u7
	prog_lin
	setbf 0x15 0x41 0
	run_boot boot_mp1
}

proc axi_setclrw {a s c} {
	stm32mp15x.axi mem2array old 32 $a 1
	stm32mp15x.axi mww $a [expr ($old(0)&~$c)|$s]
}

proc gpio_base {name} {
	scan $name %c ord
	if {$name=="Z"} then {
		stm32mp15x.axi mww 0x50000210 1
		return 0x54004000
	}
	# enable clock
	stm32mp15x.axi mww 0x50000a28 [expr 1<<($ord-65)]
	format "0x%X" [expr 0x50002000+($ord - 65)*0x1000]
}

proc gpio_info {name} {
	set base [gpio_base $name]
	stm32mp15x.axi mem2array inf 32 $base 10
	echo [format "BASE %08X MODE %08X AF L%08X H%08X I%04X O%04X" $base $inf(0) $inf(8) $inf(9) $inf(4) $inf(5)]
}

# mode 0-3:I/O/A/Z
proc gpio_mode {name bit mode alt} {
	set base [gpio_base $name]
	axi_setclrw $base [expr $mode<<($bit*2)] [expr 3<<($bit*2)]
	if $mode==2 then {
		set base [expr $base+0x20]
		if $bit>=8 then {
			set base [expr $base+0x4]
			set bit [expr $bit-8]
		}
		axi_setclrw $base [expr $alt<<($bit*4)] [expr 15<<($bit*4)]
	}
}

proc gpio_speed {name bit spd} {
	set base [gpio_base $name]
	axi_setclrw [expr $base+8] [expr $spd<<($bit*2)] [expr 3<<($bit*2)]
}

proc gpio_out {name bit v} {
	set base [gpio_base $name]
	axi_setclrw [expr $base+0x14] [expr $v<<$bit] [expr 1<<$bit]
}

proc rcc_mco {id what div} {
	set v [expr 0x1000|$what|(($div-1)<<4)]
	stm32mp15x.axi mww [expr 0x50000800+4*$id-4] $v
}

proc axi_read {addr} {
	# need to read twice (TODO?)
	stm32mp15x.axi mem2array r0 32 $addr 1
	stm32mp15x.axi mem2array r1 32 $addr 1
	return $r1(0)
}

proc get_boot_mode {} {
	format "mode %x insn %x" [axi_read 0x5c00a148] [axi_read 0x5c00a144]
}

proc set_boot_mode {x} {
	stm32mp15x.axi mww 0x50001000 0x100
	stm32mp15x.axi mww 0x5c00a148 [expr $x|0xfab20000]
}

# apply boot flags if nonzero
proc setbf {a b c} {
	set cnt 0
	set v 0
	if $a!=0 then {
		set v [expr $v|($a<<(8*$cnt))]
		set cnt [expr $cnt+1]
	}
	if $b!=0 then {
		set v [expr $v|($b<<(8*$cnt))]
		set cnt [expr $cnt+1]
	}
	if $c!=0 then {
		set v [expr $v|($c<<(8*$cnt))]
		set cnt [expr $cnt+1]
	}
	set xo [expr $a^$b^$c]
	set xo [expr ($xo^($xo>>4))&0xf]
	set v [expr $v|($xo<<(8*$cnt))]
	echo [format "%X" $v]
	
	stm32mp15x.axi mww 0x50001000 0x100
	stm32mp15x.axi mww 0x5c00a148 $v
}

proc eth_info {} {
	echo "SYSCFG/AHB6EN:"
	stm32mp15x.axi mdw 0x50020004
	stm32mp15x.axi mdw 0x50000218
}

proc en_bsec {} {
	# try enable BSEC (only in not in non-secure mode)
	mww 0x5c005000 15
	if [expr [mrw 0x5c005000] & 1]!=1 then {
		echo "BSEC not active"
		return 1
	}
	return 0
}

proc read_otp {n} {
	en_bsec
	mww 0x5c005004 [expr $n & 127]
	mem2array inf 32 [expr 0x5c005200+$n*4] 1
	return [format "0x%X" $inf(0)]
}

# MP1 CFG9, TC58: 0xA0420000 1 01 0|0 000|0100|0 0 10|0 (4k/64/2048)
# write_otp 9 0xA0420000
# MP1 CFG9, W25N: 0x80220000 1 00 0|0 000|0010|0 0 10|0 (2k/64/1024)
# manual set QSPI pins:
# QUADSPI_CLK	  PF10 (AF9) QUADSPI_BK1_NCS PB6 (AF10)
# QUADSPI_BK1_IO0 PF8 (AF10) QUADSPI_BK1_IO1 PF9 (AF10)
# CFG5: 0x6A9226A2  CFG6: 0x68A269A2
# CFG7: 0x850AC509 - enable osc, led on
# CFG3: 1 (use gpio above)
proc write_otp {n val} {
	if [en_bsec] then {
		return 1
	}
	mww 0x5c005008 $val
	mww 0x5c005004 [expr ($n & 127)|0x100]
	read_otp $n
}
