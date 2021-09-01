----------------------------------------------------------------------------------
--Copyright (C) 2020 by DOHI, Yutaka <dohi@bedesign.jp>
--
--Permission to use, copy, modify, and/or distribute this software for any purpose
--with or without fee is hereby granted.
--
--THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES WITH
--REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY AND
--FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY SPECIAL, DIRECT,
--INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
--OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER
--TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF
--THIS SOFTWARE.
----------------------------------------------------------------------------------
--(Zero Clause BSD license)


-- test bench for bop_transmitter/bop_receiver
-- Rev.00   04/Dec./2020 created

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;
USE std.textio.all;
use ieee.std_logic_textio.all;


entity tb_bop is
    generic (
        tx_ctl_file     : string := "tb_bop_cmd.txt";
        rx_log_file     : string := "tb_bop_log.txt";
        clk_period      : time := 10 ns;
        clk_delay       : time := 1 ns;
        clk_freq        : integer := 100_000_000;   -- 100MHz
        devided_freq    : integer :=   4_000_000;   -- 4MHz
        share_flag  : boolean   := true;        -- share open/close flags
        share_zero  : boolean   := true;        -- share zero adjacent flags
        fill_flag   : boolean   := true;        -- send flags during idle
        transparent : boolean   := false;       -- if true, FSC is not generate
        invert_crc  : boolean   := true;        -- ITU-T X.25, ISO/IEC 13239 Annex A said to send inverted CRC for FCS
        POLYNOMIAL  : std_logic_vector(15 downto 0) := x"1021"  -- CRC-16-CCITT (CRC-CCITT)
    );
end tb_bop;


architecture testbench of tb_bop is

    component clk_devider is
    generic (
        clk_freq        : integer := 100_000_000;
        devided_freq    : integer :=   2_048_000
    );
    port (
        CLK     : in    std_logic;
        RESETn  : in    std_logic;
        CLKDEV  : out   std_logic
    );
    end component;

    component bop_transmitter is
    generic (
        share_flag  : boolean   := true;        -- share open/close flags
        share_zero  : boolean   := true;        -- share zero adjacent flags
        fill_flag   : boolean   := true;        -- send flags during idle
        transparent : boolean   := false;       -- if true, FSC is not generate
        invert_crc  : boolean   := true;        -- ITU-T X.25, ISO/IEC 13239 Annex A said to send inverted CRC for FCS
        POLYNOMIAL  : std_logic_vector(15 downto 0) := x"1021"  -- CRC-16-CCITT (CRC-CCITT)
    );
    port (
        CLK         : in    std_logic;      -- base clock
        RESETn      : in    std_logic;      -- async reset
        TXRESET     : in    std_logic;      -- sync tx reset
        TXCn        : in    std_logic;      -- tx clock from comm line (must less than CLK/16)
        TXD         : out   std_logic;      -- tx data to comm line
        START_REQ   : in    std_logic;      -- frame start request
        ABORT       : in    std_logic;      -- frame abort
        LAST        : in    std_logic;      -- last data of frame
        LAST_SIZE   : in    std_logic_vector(2 downto 0) := "111";  -- number of trasmit bit at last octet -1
        DATA        : in    std_logic_vector(7 downto 0);   -- frame data (last octet should LSB justified)
        ACK         : out   std_logic       -- ack for START_REQ/LAST/DATA (next data request)
    );
    end component;

    component bop_receiver is
    generic (
        invert_crc  : boolean   := true;        -- ITU-T X.25, ISO/IEC 13239 Annex said to send inverted CRC at FCS
        POLYNOMIAL  : std_logic_vector(15 downto 0) := x"1021"  -- CRC-16-CCITT (CRC-CCITT)
    );
    port (
        CLK         : in    std_logic;      -- base clock
        RESETn      : in    std_logic;      -- async reset
        RXRESET     : in    std_logic;      -- sync rx reset
        RXCn        : in    std_logic;      -- rx clock from comm line (must less than CLK/16)
        RXD         : in    std_logic;      -- rx data from comm line
        SOF         : out   std_logic;      -- start of frame, contains at least 1 bit in DATA
        SIZE        : out   std_logic_vector(2 downto 0) := "111";  -- number of recieved bit -1
        EOF         : out   std_logic;      -- end of frame, not contins DAATA
        ABORT       : out   std_logic;      -- abort when end of frame
        DATA        : out   std_logic_vector(7 downto 0);   -- frame data (MSB justified if non full octed received)
        CRC_ERROR   : out   std_logic;      -- error shows with EOF
        STB         : out   std_logic       -- strobe for liatchin DATA
    );
    end component;

    signal      simend, txend                       : boolean := false;
    signal      CLK, RESETn                         : std_logic;
    signal      TXCn, TXD, RXCn, RXD                : std_logic;
    signal      TX_RESET, RX_RESET                  : std_logic;
    signal      TX_START, TX_ABORT, TX_LAST, TX_ACK : std_logic;
    signal      RX_SOF, RX_ABORT, RX_EOF, RX_STB    : std_logic;
    signal      RX_CRCERR                           : std_logic;
    signal      TX_LAST_SIZE, RX_SIZE               : std_logic_vector(2 downto 0);
    signal      TX_DATA, RX_DATA                    : std_logic_vector(7 downto 0);

begin

    -- clock driver
    process
    begin
        CLK <= '1';
        while (simend = false) loop
            wait for clk_period/2;
            CLK <= not CLK;
        end loop;
        wait;
    end process;

    -- TXCn, RXCn
    inst_clk_devider: clk_devider
        generic map (
            clk_freq        => clk_freq,
            devided_freq    => devided_freq
        )
        port map (
            CLK     => CLK,
            RESETn  => RESETn,
            CLKDEV  => TXCn
        );
    RXCn <= TXCn;

    -- frame transmission
    process
        file        tx_ctl          : text;
        variable    in_buff         : line;
        variable    cmd, cp         : character;
        variable    param           : integer;
        variable    data_length     : integer;
        variable    last_bit_count  : integer range 0 to 7;
        variable    txdata          : std_logic_vector(7 downto 0);
        variable    first, last     : boolean;
    begin
        txend <= false; first := true;
        RESETn <= '0';  TX_RESET <= '0';    RX_RESET <= '0';
        TX_START <= '0';    TX_ABORT <= '0';    TX_LAST <= '0'; TX_DATA <= (others => '1'); TX_LAST_SIZE <= "000";
        file_open(tx_ctl, tx_ctl_file, read_mode);
        wait until (CLK = '0'); wait until (CLK = '1');     -- synch to CLK rising edge
        while (not endfile(tx_ctl)) loop
            readline (tx_ctl, in_buff);
            -- command interpret
            read(in_buff, cmd);
            case (cmd) is
            when 'C' => -- wait clock period
                read(in_buff, param);
                wait for clk_period * (param);
            when 'R' => -- RESETn
                read(in_buff, param);
                if (param = 0) then
                    RESETn <= '0' after clk_delay;
                else
                    RESETn <= '1' after clk_delay;
                end if;
                wait until (CLK = '0'); wait until (CLK = '1');     -- synch to CLK rising edge
            when 't' => -- TX_RESET (init transmitter)
                read(in_buff, param);
                wait until (CLK = '0'); wait until (CLK = '1'); wait for clk_delay;
                if (param = 0) then
                    TX_RESET <= '0';
                else
                    TX_RESET <= '1';
                end if;
            when 'r' => -- RX_RESET (init receiver)
                read(in_buff, param);
                wait until (CLK = '0'); wait until (CLK = '1'); wait for clk_delay;
                if (param = 0) then
                    RX_RESET <= '0';
                else
                    RX_RESET <= '1';
                end if;
            when 'F' => -- frame transmission
                first := true;  last := false;
                while (last = false) loop
                    wait until (CLK = '0'); wait until (CLK = '1'); wait for clk_delay;
                    if (first = true) then
                        TX_START <= '1';
                        first := false;
                    end if;
                    hread(in_buff, txdata);
                    TX_DATA <= txdata;
                    read(in_buff, cp);
                    if (cp = '@' or cp = '#') then
                        read(in_buff, param);
                        if (param > 7) then
                            TX_LAST_SIZE <= "111";
                        else
                            TX_LAST_SIZE <= conv_std_logic_vector(param, 3);
                        end if;
                        TX_LAST <= '1';
                        last := true;
                        if (cp = '#') then
                            TX_ABORT <= '1';
                        end if;
                    end if;
                    wait until (TX_ACK = '1');
                    wait until (CLK = '0'); wait until (CLK = '1'); wait for clk_delay;
                    TX_START <= '0';    TX_ABORT <= '0';    TX_LAST <= '0';
                end loop;
            when others =>  -- coment line
                null;
            end case;
        end loop;
        file_close(tx_ctl);
        txend <= true;
        wait;
    end process;
    
    process
        file        rx_log              : text;
        variable    out_buff            : line;
        variable    lastsize, dtcount   : integer;
    begin
        simend <= false;
        lastsize := 0;  dtcount := 0;
        file_open(rx_log, rx_log_file, write_mode);
        write(out_buff, string'("-- Simulation log for tb_bop.vhd"));
        writeline(rx_log, out_buff);
        wait for clk_period;
        while (simend = false) loop
            wait until (CLK = '0'); wait until (CLK = '1');    wait for clk_delay;
            if (RX_SOF = '1') then
                write(out_buff, now, right, 12, ns);
                write(out_buff, string'(" RCV:"));
                dtcount := 0;
            end if;
            if (RX_STB = '1') then
                hwrite(out_buff, RX_DATA, right, 3);
                lastsize := conv_integer(RX_SIZE);
                dtcount := dtcount + 1;
            end if;
            if  (RX_EOF = '1') then
                write(out_buff, string'(" octet="));
                write(out_buff, dtcount);
                write(out_buff, string'(" last_size="));
                write(out_buff, lastsize);
                if (RX_CRCERR = '1') then
                    write(out_buff, string'(" with CRC ERROR"));
                end if;
                writeline(rx_log, out_buff);
                if (txend = true) then
                    simend <= true;
                end if;
            end if;
            if (RX_ABORT = '1') then
                write(out_buff, string'(" octet="));
                write(out_buff, dtcount);
                write(out_buff, string'(" last_size="));
                write(out_buff, lastsize);
                write(out_buff, string'(" with ABORT"));
                writeline(rx_log, out_buff);
                if (txend = true) then
                    simend <= true;
                end if;
            end if;
            if (RX_RESET = '1') then
                if (dtcount /= 0) then
                    writeline(rx_log, out_buff);
                end if;
                write(out_buff, now, right, 12, ns);
                write(out_buff, string'(" Receiver Reset"));
                writeline(rx_log, out_buff);
            end if;
        end loop;
        write(out_buff, now, right, 8, ns);
        write(out_buff, string'(" END of SIM"));
        writeline(rx_log, out_buff);
        wait for clk_period * 10;
        wait;
    end process;
    
               
    -- module under test
    
    inst_bop_transmitter: bop_transmitter
        generic map (
            share_flag      => share_flag,
            share_zero      => share_zero,
            fill_flag       => fill_flag,
            transparent     => transparent,
            invert_crc      => invert_crc,
--            invert_crc      => not invert_crc,  -- for emulating CRC error
            POLYNOMIAL      => POLYNOMIAL
        )
        port map (
            CLK         => CLK,
            RESETn      => RESETn,
            TXRESET     => TX_RESET,
            TXCn        => TXCn,
            TXD         => TXD,
            START_REQ   => TX_START,
            ABORT       => TX_ABORT,
            LAST        => TX_LAST,
            LAST_SIZE   => TX_LAST_SIZE,
            DATA        => TX_DATA,
            ACK         => TX_ACK
        );
    RXD <= TXD;
    inst_bop_receiver: bop_receiver
        generic map (
            invert_crc      => invert_crc,
            POLYNOMIAL      => POLYNOMIAL
        )
        port map (
            CLK         => CLK,
            RESETn      => RESETn,
            RXRESET     => RX_RESET,
            RXD         => RXD, 
            RXCn        => RXCn,
            SOF         => RX_SOF,
            SIZE        => RX_SIZE,
            EOF         => RX_EOF,
            ABORT       => RX_ABORT,
            DATA        => RX_DATA,
            CRC_ERROR   => RX_CRCERR,
            STB         => RX_STB
        );
            
end testbench;
