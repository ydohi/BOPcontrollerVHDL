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

-- BOP (Bit Oriented Protocol) receiver stripping flag, and bit stuffing
-- Rev.00   04/Dec./2020 created
-- This module receive octet by octet. DATA includes A/C/I/FCS-field.
-- Any of "sharing open/close flag", "sharing '0' between adjacent flags", "fill flag during idle or not" allowable. 
-- Check FCS according to generic parameter.
-- FCS (CRC) polynomial can be choose with generic parameter. Even transparen communication, it's needed polynominal generic parameter. Recommend default.
-- Inverted FCS can check according to ITU-T X.25 and ISO/IEC 13239 Annex A with generic parameter.
-- For usual telecom, it should be invert_crc = true.
-- SOF indicates start of frame with STB. DATA contains received data.
-- EOF indicate end of frame without STB. Ignore DATA and SIZE.
-- DATA with ACK coutains received data.DATA is MSB justified if not full octet.
-- SIZE indicates bit counts-1 in DATA. If it's full octet, SIZE shows "111".
-- CRCERR indicate received CRC error with EOF. CRCERR should be ignored if transparent communication.
-- ABORT indicate received frame abort without STB.
-- DATA is including FCS, then strip it in upper module if necessory.
-- Upper module should latch DATA/SIZE with STB pulse.
-- STB/SOF/EOF/CRCERR/ABORT pulse width is 1 CLK period.
-- When received abort frame, DATA/SIZE are not available, should be ignored.

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.std_logic_arith.all;

entity bop_receiver is
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
end bop_receiver;

architecture RTL of bop_receiver is

component crc_gen is
    generic (
        invert_crc  : boolean := true;  -- ITU-T X.25, ISO/IEC 13239 Annex said to send inverted CRC at FCS
    -- choose one of following..can use any other polynomial if necessary
    -- see "Cyclic redundancy check" section in wikipedia for available polynomial
--        POLYNOMIAL  : std_logic_vector( 3 downto 0) := x"3" -- CRC-4-ITU
--        POLYNOMIAL  : std_logic_vector( 4 downto 0) := '1' & x"5"   -- CRC-5-ITU
--        POLYNOMIAL  : std_logic_vector( 5 downto 0) := "00" & x"3"  -- CRC-6-ITU
--        POLYNOMIAL  : std_logic_vector( 6 downto 0) := "000" & x"9" -- CRC-7
--        POLYNOMIAL  : std_logic_vector( 7 downto 0) := x"07"    -- CRC-8-ATM
--        POLYNOMIAL  : std_logic_vector( 7 downto 0) := x"8D"    -- CRC-8-CCITT
--        POLYNOMIAL  : std_logic_vector(14 downto 0) := "100" & x"599"   -- CRC-15-CAN
        POLYNOMIAL  : std_logic_vector(15 downto 0) := x"1021"  -- CRC-16-CCITT (CRC-CCITT)
--        POLYNOMIAL  : std_logic_vector(15 downto 0) := x"8005"  -- CRC-16
--        POLYNOMIAL  : std_logic_vector(31 downto 0) := x"04C11DB7"  -- CRC-32
--        POLYNOMIAL  : std_logic_vector(63 downto 0) := x"000000000000001B"  -- CRC-64-ISO
    );
    port (
        CLK         : in    std_logic;          -- base clock
        RESETn      : in    std_logic;          -- async reset
        INIT_CRC    : in    std_logic;          -- initial shift reg.
        ENB         : in    std_logic;          -- shift enable
        DIN         : in    std_logic;          -- serial data in
        DIN_AVAIL   : in    std_logic;          -- DIN is available to CRC generate
        DOUT        : out   std_logic;          -- serial data out
        CRCERR      : out   std_logic;          -- received crc error indication (after last crc received)
        CRC         : out   std_logic_vector(POLYNOMIAL'high downto POLYNOMIAL'low) -- current CRC
    );
end component;

component rx_frame_bitstuff is
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
end component;

    type state_type is (idle, receive_data, put_rx_data, receive_eof, receive_abort);
    signal  fsm_state   : state_type;
    signal  RX_REG      : std_logic_vector(7 downto 0);
    signal  RX_SOF      : std_logic;
    signal  RX_EOF      : std_logic;
    signal  RX_ABORT    : std_logic;
    signal  RX_DATA     : std_logic;
    signal  RX_STB      : std_logic;
    signal  INIT_CRC    : std_logic;
    signal  RX_CRCERR   : std_logic;
    signal  CRC_REG     : std_logic_vector(POLYNOMIAL'high downto POLYNOMIAL'low);


begin

    process (CLK, RESETn)
    begin
        if (RESETn = '0') then
            RX_REG <= (others => '1');
        elsif (rising_edge(CLK)) then
            if (RXRESET = '1') then
                RX_REG <= (others => '1');
            elsif (RX_STB = '1') then
                RX_REG <= RX_DATA & RX_REG(7 downto 1);
            end if;
        end if;
    end process;

    -- fsm
    process (CLK, RESETn)
        variable    first_flag  : boolean := true;
        variable    last_flag   : boolean :=false;
        variable    abort_flag  : boolean := false;
        variable    bit_counter : integer range 0 to 7 := 7;
    begin
        if (RESETn = '0') then
            fsm_state <= idle;
            bit_counter := 0;
            first_flag := true; last_flag := false; abort_flag := false;
            SOF <= '0';  EOF <= '0';  ABORT <= '0';  STB <= '0';
            INIT_CRC <= '1';  CRC_ERROR <= '0';
            DATA <= (others =>'1');
            SIZE <= "111";
        elsif (rising_edge(CLK)) then
            if (RXRESET = '1') then
                fsm_state <= idle;
                bit_counter := 0;
                first_flag := true; last_flag := false; abort_flag := false;
                SOF <= '0';  EOF <= '0';  ABORT <= '0';  STB <= '0';
                INIT_CRC <= '1';  CRC_ERROR <= '0';
                first_flag := true;
                DATA <= (others =>'1');
                SIZE <= "111";
            else
                case (fsm_state) is
                when idle =>
                    SOF <= '0';  EOF <= '0';  ABORT <= '0';  STB <= '0';
                    INIT_CRC <= '0';  CRC_ERROR <= '0';
                    if (RX_SOF = '1') then
                        fsm_state <= receive_data;
                        bit_counter := 1;
                    else
                        bit_counter := 0;
                    end if;
                    first_flag := true; last_flag := false; abort_flag := false;
                when receive_data =>
                    SOF <= '0';  EOF <= '0';  ABORT <= '0';  STB <= '0';
                    INIT_CRC <= '0';  CRC_ERROR <= '0';
                    if (RX_ABORT = '1') then
                        if (bit_counter = 0) then
                            fsm_state <= receive_abort;
                        else
                            fsm_state <= put_rx_data;
                            bit_counter := bit_counter - 1;
                        end if;
                        abort_flag := true;
                    elsif (RX_EOF = '1') then
                        if (bit_counter = 0) then
                            fsm_state <=  receive_eof;
                        else
                            fsm_state <= put_rx_data;
                            bit_counter := bit_counter - 1;
                        end if;
                        last_flag := true;
                    elsif (RX_STB = '1') then
                        if (bit_counter = 7) then
                            fsm_state <= put_rx_data;
                        else
                            bit_counter := bit_counter + 1;
                        end if;
                    end if;
                when put_rx_data =>
                    EOF <= '0';  ABORT <= '0';  STB <= '1';
                    SIZE <= conv_std_logic_vector(bit_counter, 3);
                    if (first_flag = true) then
                        SOF <= '1';
                        first_flag := false;
                    else
                        SOF <= '0';
                    end if;
                    INIT_CRC <= '0';  CRC_ERROR <= '0';
                    if (abort_flag = true) then
                        fsm_state <= receive_abort;
                    elsif (last_flag = true) then
                        fsm_state <= receive_eof;
                    else
                        fsm_state <= receive_data;
                    end if;
                    bit_counter := 0;
                    DATA <= RX_REG;
                 when receive_eof =>
                    SOF <= '0';  EOF <= '1';  ABORT <= '0';  STB <= '0';
                    INIT_CRC <= '1';  CRC_ERROR <= RX_CRCERR;
                    fsm_state <= idle;
                    bit_counter := 0;
                when receive_abort =>
                    SOF <= '0';  EOF <= '0';  ABORT <= '1';  STB <= '0';
                    INIT_CRC <= '1';  CRC_ERROR <= '0';
                    fsm_state <= idle;
                    bit_counter := 0;
                when others =>
                    SOF <= '0';  EOF <= '0';  ABORT <= '0';  STB <= '0';
                    INIT_CRC <= '1';  CRC_ERROR <= '0';
                    fsm_state <= idle;
                    bit_counter := 0;
                end case;
            end if;
        end if;
    end process;

    inst_rx_frame_bitstuff: rx_frame_bitstuff
        port map (
            CLK         => CLK,
            RESETn      => RESETn,
            RXRESET     => RXRESET,
            RXCn        => RXCn,
            RXD         => RXD,
            SOF         => RX_SOF,
            EOF         => RX_EOF,
            ABORT       => RX_ABORT,
            DATA        => RX_DATA,
            STB         => RX_STB
        );
            

    inst_crc_gen : crc_gen
        generic map (
            invert_crc  => invert_crc,
            POLYNOMIAL  => POLYNOMIAL
        )
        port map (
            CLK         => CLK,
            RESETn      => RESETn,
            INIT_CRC    => INIT_CRC,
            ENB         => RX_STB,
            DIN         => RX_DATA,
            DIN_AVAIL   => '1',
            DOUT        => open,
            CRCERR      => RX_CRCERR,
            CRC         => CRC_REG
        );


end RTL;
