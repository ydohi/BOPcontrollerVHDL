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

-- Transmit frame for bit oriented protocol as like HDLC
-- Rev.00   04/Dec./2020 created
-- CLK freq should be enough faster, otherwise skew between TXCn and TXD would be an issue.
-- When CLK freq is less than 16 * TXCn, recommend sychronize TXD to TXCn at output stage in device.
-- CLK freq must be faster than 4 * TXCn. otherwise it might cannot make correct frame.
-- When DTE, TXCn should have appropriate glitch filter.
-- TXD transition after TXCn falling edge.
-- This is fit for ITU-T V.24/V.28 with general RS-232 transcevers which invert voltage high/low level.


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity tx_frame_bitstuff is
    generic (
        share_flag  : boolean   := true;        -- share open/close flags
        share_zero  : boolean   := true;        -- share zero adjacent flags
        fill_flag   : boolean   := true         -- send flags during idle
    );
    port (
        CLK         : in    std_logic;          -- system clock 
        RESETn      : in    std_logic;          -- asynch reset
        TXRESET     : in    std_logic;          -- synch transmitter reset
        TXCn        : in    std_logic;          -- tx clock from comm line (must less than CLK/16)
        TXD         : out   std_logic;          -- tx data to comm line
        SOF         : in    std_logic;          -- start of frame (with 1st DATA)
        EOF         : in    std_logic;          -- end of frame (with last DATA)
        ABORT       : in    std_logic;          -- abort when end of frame (sensed with EOF only)
        DATA        : in    std_logic;          -- transmit bit stream
        ACK         : out   std_logic           -- acknowlidge for SOF/EOF/ABORT/DATA
    );
end tx_frame_bitstuff;



architecture RTL of tx_frame_bitstuff is

    type state_type is (idle, open_flag, send_data, send_abort, close_flag);
    signal fsm_state    : state_type;
    signal txc_tmg      : std_logic;
    signal counter      : integer range 0 to 7;

begin

    -- txc timing
    process (CLK, RESETn)
        variable txc_delay  : std_logic := '0';
    begin
        if (RESETn = '0') then
            txc_tmg <= '0';
            txc_delay := '0';
        elsif (rising_edge(CLK)) then
            if (txc_delay = '1' and TXCn = '0') then
                txc_tmg <= '1';
            else
                txc_tmg <= '0';
            end if;
            txc_delay := TXCn;
        end if;
    end process;
    
    -- fsm
    process (CLK, RESETn)
    begin
        if (RESETn = '0') then
            TXD <= '1';
            fsm_state <= idle;
            counter <= 7;
        elsif (rising_edge(CLK)) then
            if (TXRESET = '1') then
                TXD <= '1';
                fsm_state <= idle;
                counter <= 7;
            elsif (txc_tmg = '1') then
                case (fsm_state) is
                when idle =>
                    TXD <= '1';
                    if (counter = 0) then
                        if (SOF = '1' or fill_flag = true) then
                            fsm_state <= open_flag;
                            counter <= 7;
                        end if;
                    else
                        counter <= counter - 1;
                    end if;
                when open_flag =>
                    case (counter) is
                    when 0 | 7 =>   TXD <= '0';
                    when others =>  TXD <= '1';
                    end case;
                    if (counter = 0) then
                        if (SOF = '1') then
                            fsm_state <= send_data;
                            counter <= 5;   -- bit stuff count
                        else
                            if (share_zero = true) then
                                counter <= 6;   -- need zero only flag end
                            else
                                counter <= 7;   -- need zero each flag end
                            end if;
                        end if;
                    else
                        counter <= counter - 1;
                    end if;
                when send_data =>
                    if (counter = 0) then   -- bit sutuffing (insert zero)
                        TXD <= '0';
                        counter <= 5;   -- bit stuff count
                    else
                        TXD <= DATA;
                        if (EOF = '1') then
                            if (ABORT = '1') then
                                fsm_state <= send_abort;
                                counter <= 5;   -- send one at least this count +1 when abort
                            elsif (share_flag = true) then
                                fsm_state <= open_flag;
                                counter <= 7;   -- need zero each flag end
                            else
                                fsm_state <= close_flag;
                                counter <= 7;   -- need zero each flag end
                            end if;
                        else
                            if (DATA = '1') then
                                counter <= counter - 1;
                            else
                                counter <= 5;   -- bit stuff count
                            end if;
                        end if;
                    end if;
                when send_abort =>
                    TXD <= '1';
                    if (counter = 0) then
                        fsm_state <= idle;
                        counter <= 7;
                    else
                        counter <= counter - 1;
                    end if;
                when close_flag =>
                    case (counter) is
                    when 0 | 7 =>   TXD <= '0';
                    when others =>  TXD <= '1';
                    end case;
                    if (counter = 0) then
                        if (SOF = '1' or fill_flag = true) then
                            fsm_state <= open_flag;
                            if (share_zero = true) then
                                counter <= 6;
                            else
                                counter <= 7;
                            end if;
                        else
                            fsm_state <= idle;
                            counter <= 7;
                         end if;
                    else
                        counter <= counter - 1;
                    end if;
                when others =>
                    fsm_state <= idle;
                    counter <= 7;
                end case;
            end if;
        end if;
    end process;

    -- ACK
    process (CLK, RESETn) begin
        if (RESETn = '0') then
            ACK <= '0';
        elsif (rising_edge(CLK)) then
            case (fsm_state) is
            when send_data =>
                if (counter /= 0) then
                    ACK <= txc_tmg;
                else
                    ACK <= '0';
                end if;
            when others =>
                ACK <= '0';
            end case;
        end if;
    end process;
            

end RTL;
