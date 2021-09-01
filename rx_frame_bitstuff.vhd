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

--Receive frame for bit oriented protocol as like HDLC
-- Rev.00   04/Dec./2020 created
-- CLK freq must be faster than 4 * RXCn. otherwise it might cannot sense correct frame.
-- RXCn (when DTE) and RXD should have appropriate glitch filter.
-- RXD sample after RXCn rising edge.
-- This is fit for ITU-T V.24/V.28 with general RS-232 transcevers which invert voltage high/low level.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity rx_frame_bitstuff is
    port (
    CLK         : in    std_logic;          -- system clock 
    RESETn      : in    std_logic;          -- asynch reset
    RXRESET     : in    std_logic;          -- sync reciever reset
    RXCn        : in    std_logic;          -- rx clock from comm line (must less than CLK/16)
    RXD         : in    std_logic;          -- rx data from comm line
    SOF         : out   std_logic;          -- start of frame (with 1st DATA)
    EOF         : out   std_logic;          -- end of frame (with last DATA)
    ABORT       : out   std_logic;          -- abort when end of frame
    DATA        : out   std_logic;          -- receive bit stream
    STB         : out   std_logic           -- strobe for liatchin DATA
);
end rx_frame_bitstuff;

architecture RTL of rx_frame_bitstuff is

    type state_type is (idle, wait_start, receive_data);
    signal fsm_state    : state_type;
    signal rxc_tmg      : std_logic;
    signal rx_shift     : std_logic_vector (7 downto 0);
    signal rx_shift_dly : std_logic;
    
    signal detect_flag  : std_logic;
    signal detect_abort : std_logic;
    signal counter      : integer range 0 to 7;

begin

    -- rxc timing
    process (CLK, RESETn)
        variable rxc_delay  : std_logic := '0';
    begin
        if (RESETn = '0') then
            rxc_tmg <= '0';
            rxc_delay := '0';
        elsif (rising_edge(CLK)) then
            if (rxc_delay = '0' and RXCn = '1') then
                rxc_tmg <= '1';
            else
                rxc_tmg <= '0';
            end if;
            rxc_delay := RXCn;
        end if;
    end process;

    -- flag and abort detect
    process (CLK, RESETn)
    begin
        if (RESETn = '0') then
            detect_flag <= '0';
            rx_shift_dly <= '1';
            rx_shift <= (others => '1');
            DATA <= '1';
            rx_shift_dly <= '1';
        elsif (rising_edge(CLK)) then
            if (RXRESET = '1') then
                detect_flag <= '0';
                detect_abort <= '1';
                rx_shift <= (others => '1');
                DATA <= '1';
                rx_shift_dly <= '1';
            elsif (rxc_tmg = '1') then
                rx_shift <= RXD & rx_shift(7 downto 1);
                DATA <= rx_shift_dly;
                rx_shift_dly <= rx_shift(0);
                if (rx_shift = x"7E") then
                    detect_flag <= '1';
                else
                    detect_flag <= '0';
                end if;
                case (rx_shift) is
                when "11111110" | "11111111" | "01111111" =>
                    detect_abort <= '1';
                when others =>
                    detect_abort <= '0';
                end case;
            end if;
        end if;
    end process;

    -- fsm
    process (CLK, RESETn)
    begin
        if (RESETn = '0') then
            fsm_state <= idle;
            counter <= 7;
        elsif (rising_edge(CLK)) then
            if (RXRESET = '1') then
                fsm_state <= idle;
                counter <= 7;
            elsif (rxc_tmg = '1') then
                case (fsm_state) is
                when idle =>
                    counter <= 7;   -- preset flag finish detect counter
                    if (detect_flag = '1') then -- detect flag
                        fsm_state <= wait_start;
                    end if;
                when wait_start =>
                    if (detect_flag = '1') then -- not started, maybe flag fill petern
                        counter <= 7;   -- preset flag finish detect counter
                    elsif (detect_abort = '1') then -- line idle
                        fsm_state <= idle;
                        counter <= 7;
                    elsif (counter = 0) then    -- frame started
                        fsm_state <= receive_data;
                        if (rx_shift_dly = '0') then
                            counter <= 5;   -- preset bit stuffing counter
                        else
                            counter <= 4;   -- already received '1' then bit stuffing counter starts from 4
                        end if;
                    else
                        counter <= counter - 1;
                    end if;
                when receive_data =>
                    if (detect_abort = '1') then    -- received frame aborted
                        fsm_state <= idle;
                        counter <= 7;
                    elsif (detect_flag = '1') then  -- recieved frame closed
                        fsm_state <= wait_start;
                        counter <= 7;   -- preset flag finish detect counter
                    elsif (rx_shift_dly = '0') then
                        counter <= 5;   -- preset bit stuffing counter
                    elsif (counter /= 0) then
                        counter <= counter - 1;
                    end if;
                when others =>
                    counter <= 7;
                    fsm_state <= idle;
                end case;
            end if;
        end if;
    end process;

    -- DATA, STB, SOF, EOF, ABORT
    process (RESETn, CLK)
    begin
        if (RESETn = '0') then
            STB <= '0';
            SOF <= '0';
            EOF <= '0';
            ABORT <= '0';
        elsif (rising_edge(CLK)) then
            case (fsm_state) is
            when wait_start =>
                if (detect_flag = '0' and counter = 0) then
                    STB <= rxc_tmg;
                    SOF <= rxc_tmg;
                else
                    STB <= '0';
                    SOF <= '0';
                end if;
                EOF <= '0';
                ABORT <= '0';
            when receive_data =>
                SOF <= '0';
                if (detect_abort = '1') then
                    STB <= '0';
                    EOF <= '0';
                    ABORT <= rxc_tmg;
                elsif (detect_flag = '1') then
                    STB <= '0';
                    EOF <= rxc_tmg;
                    ABORT <= '0';
                elsif (counter = 0) then    -- receved 5 consecutive '1's
                    STB <= '0';     -- bit stuffing
                    EOF <= '0';
                    ABORT <= '0';
                else
                    STB <= rxc_tmg;
                    EOF <= '0';
                    ABORT <= '0';
                end if;
            when others =>
                STB <= '0';
                SOF <= '0';
                EOF <= '0';
                ABORT <= '0';
            end case;
        end if;
    end process;
    
             
end RTL;
