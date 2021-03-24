# SOMP1 eval board revD

## Description

The eval board allows evaluating and programming of SOMP1 modules.
It contains gigabit ethernet, JTAG and USART access via micro USB,
USB-C connected to MP1 OTG controller, 2.4/5GHz WiFi module,
backup battery, accelerometer, temperature and humidity sensors.

Also 7x2 2mm connector with DSI output and 40pin Raspberry compatible
GPIO connector.
The DSI display is not included in STM32MP151 version.

The schematic is [here](./somp1_evalD_schematic.pdf).

## Initial power-up

Module comes with preinstalled minimal buildrood based distro and
some examples for EVAL board.
Also DTB for EVAL board is preinstalled.
Connect micro-USB connector marked USB3 to a computer. Under Linux
new devices (e.g. /dev/USB0 and USB1) are created.

Run minicom on second one:
```
minicom -D /dev/ttyUSB1
```
press Enter and you should see:
```
Welcome to LUMP
lump1 login:
```
You can login as `root` with default password `121212`.

On Windows you may need to install FTDI drivers first, depends on your version.
It is not detailed because you need Linux machine for serious Linux based SOM 
developement.

## Console connection details

SOMP1 module bootloader and DTB settings uses USART1 as console by default.
EVAL specific DTB is changed in this way:
```
/ {
        aliases {
                serial0 = &uart4;
        };
};
```
so that FTDI connected UART4 (PH13 and PC11 SOM ports and FTDI BDBUS) can be used. 
The bootloader still uses USART1 and you can see only Linux based messages 
and console on UART4.

We use our [DTBoot](https://github.com/cleartex/dtboot) bootloader and it offers
several quick ways to redirect output to UART4 too:

- set bootloader flag 1 by debugger or from running Linux
- change dtboot section in DTB
- TODO: explain both ways in more detail

## Debugger connection

ADBUS port of FTDI USB chip (ADBUS supports MPSSE) is connected to JTAG and NRST
pins of module (**thus don't use flex connected debugger when SOMP1 is in EVAL**).

Use [openocd](http://openocd.org/) software to connect to the SOMP1 via this port.
You can then debug code, upload/reflash firmware, change bootloader settings 
at runtime etc.

There are openocd configs [here](./openocd/). 
Example session:
```
$ openocd -f ft_lumpberryC.cfg -f stm32mp_s.cfg -f mp1_prog.tcl
Open On-Chip Debugger 0.10.0+dev-01379-g6ec2ec4d3-dirty (2020-08-15-18:45)
Licensed under GNU GPL v2
....
Info : Listening on port 4444 for telnet connections
Info : clock speed 1000 kHz
Info : JTAG tap: stm32mp15x.tap tap/device found: 0x6ba00477 (mfg: 0x23b (ARM Ltd.), part: 0xba00, ver: 0x6)
Info : JTAG tap: stm32mp15x.clc.tap tap/device found: 0x06500041 (mfg: 0x020 (STMicroelectronics), part: 0x6500, ver: 0x0)
Info : stm32mp15x.cpu0: hardware has 6 breakpoints, 4 watchpoints
Info : starting gdb server for stm32mp15x.cpu0 on 3333
Info : Listening on port 3333 for gdb connections
Info : starting gdb server for stm32mp15x.cpu2 on 3334
Info : Listening on port 3334 for gdb connections
```
Note that `stm32mp_s` is single-cpu config (for MP151).
Now you can connect to port 4444
```
$ telnet 127.0.0.1 4444
Escape character is '^]'.
Open On-Chip Debugger
> 
```
Now you can for example issue `reset` command to reset stuck system. You can 
also reflash various parts of NAND in case you screw something in Linux 
(like `flashcp` of invalid image over some partition).
And of course you can attach `gdb` debugger if you need to debug Linux kernel,
bootloader or MP1's M4 coprocessor code (very useful).

## Preinstalled system

See [SOMP1](README.md) docs for information about OS preinstalled on the SOMP1
module.

## Demo software

**This section is incomplete, reflects only MP151 version without display**.

There are some demoscripts in /root directory.

- `read_temperature.sh` shows simple way to read onboard sensor
- `lsomctl -i` shows informations about SOM (version, MAC, config)
- `i2cdetect -y 0` shows attached I2C device

### Ethernet

There is `KSZ9031` PHY on the eval, it is currently configured as 100MBit
and `fix_ethernet.sh` script sets some internal delay parameters (because
MP1 family can't delay TX data). The parameters needs more attention for
stable 1G connection (TODO).

There is no need for such script if you use 100Mbit only RMII PHY.

EVAL code starts `udhcpc` only at start - so that when you plug ETH cable
later, it doesn't get address by DHCP. It is means as demo only.
When testing you can always set `eth0` address manualy or start `udhcpc`
from UART console yourself. In production image you will probably use
`udhcpc -b` to keep it running.

### WiFi

There is `iw` tool and `wpa_supplicant` present. See their docs. As
simple test you can run 
```
ifconfig wlan0 up
iw wlan0 info
iw wlan0 scan
```
to see it is working. Also there is example `wpa.conf`. Edit it
with yours SSID/password and run:
```
wpa_supplicant -Dnl80211 -iwlan0 -cwpa.conf
udhcpc -i wlan0
```
and you should get valid connection on `wlan0`.

We prefer to explain it in such low-level terms/commands as we assume
you are building deeply embeded system and want to be in control.

### USB-C

TODO

### Other ports (40pin header) - UART, SPI, I2C...

You need to change (create own and include ours) DTS code and compile to DTB.
Flash DTB to `/dev/mtd2`, reboot and you will get ports activated as selected.
See DTB section of [SOMP1](README.md).

