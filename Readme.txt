VHDL BOP (Bit Oriented Protocol) controller for HDLC framing.

These modules' function is follows.
- add/strip FLAGs, and Bit Stuffing
- fill FLAGs during idle or not
- share open/close FLAGs or not
- share ZERO between adjacent FLAGs or not
- available any length/polynomial CRC in FCS field, or tranparent without FCS field
- invert FCS field for ITU-T X.25, ISO/IEC 13239 Annex A, or not
- non OCTETs frame length is available
- transmit/detect ABORT frame
- detect CRC error for non transparent frame
Need A/C field's processing at upper module and/or processor software.

Top of transmitter module is "bop_transmitter.vhd".
Top of receiver module is "bop_receiver.vhd".
Test bench for both modules is "tb_bop.vhd", stimulus control file is "tb_bop_cmd.txt".
Generate "tb_bop_log.txt" when simulation.
"clk_devider.vhd" generate TX/RX clock in test bench.
See test bench and comments in each module for detail and usage.

Each module except test bench confirmed to be synthesizable and implementationable by Xilinx Vivado with Spartan-7.
Behavioral simulation had done by Xilinx Vivado simulator. Test banch might be fit for other simulators.
Text files' default path at behavioral simulation of Vivado Simulator is
{project_top}/{project_name}.sim/sim_1/behav/xsim/

All modules are licenced with "Zero Clause BSD".
https://opensource.org/licenses/0BSD

I can't provide any support, but bug reports are welcome.
DOHI, Yutaka <dohi@bedesign.jp>

