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

-- BOP (Bit Oriented Protocol) transmitter adding flag, FCS, and bit stuffing
-- Rev.00   04/Dec./2020 created
-- This module transmits octet by octet. DATA should be including A/C-field and I-field if necessary.
-- Flag type can be selected as "sharing open/close flag", "sharing '0' between adjacent flags", "fill flag during idle or not" with generic parameters.
-- For LAP-D usage, it should be share_zero = true, fill_flag = false according to BRI multi-drop DTE scheme.
-- FCS generation can be skip and transmit transparent frame with generic parameter.
-- FCS (CRC) polynomial can be choose with generic parameter. Even transparent = true, it's needed polynominal generic parameter. Recommend default..
-- Inverted FCS can send according to ITU-T X.25 and ISO/IEC 13239 Annex A with generic parameter.
-- For usual telecom, it shjould be invert_crc = true.
-- START_REQ should set with first octet frame, clear by ACK.
-- LAST should set whith last octet at frame, clear by ACK.
-- Last DATA (for I-frame) can be non full octet, has to be LSB justified.
-- Last DATA bit count should specify bit counts-1 at LAST_SIZE. If it's full octet, LAST_SIZE should be "111".
-- START_REQ and LAST can set at a time, it causes short frame transmission.
-- For usual telecom, last DATA should be full octet. Upper layer have to fill with appropriate padding pattern.
-- DATA should update by each ACK pulse.
-- For aborting transmittion, ABORT should set instead of LASt,, clear by ACK. (Abort sequence is transmit more than 7 '1' without bit stuffing during frame.)
-- ACK width is 1 CLK period regardless START_REQ/LAST/ABORT continues or not.


library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity bop_transmitter is
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
end bop_transmitter;


architecture RTL of bop_transmitter is

component tx_frame_bitstuff is
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
end component;

component crc_gen is
    generic (
        invert_crc  : boolean := true;  -- ITU-T X.25, ISO/IEC 13239 Annex A said to send inverted CRC for FCS
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

    type state_type is (idle, get_tx_data, send_data, send_fcs);
    signal  fsm_state   : state_type;
    signal  TX_REG      : std_logic_vector(7 downto 0);
    signal  TX_SOF      : std_logic;
    signal  TX_EOF      : std_logic;
    signal  TX_ABORT    : std_logic;
    signal  TX_ACK      : std_logic;
    signal  TX_DATA     : std_logic;    -- serial tx data through CRC generator
    signal  TEMP_TX_DT  : std_logic;    -- serial tx data before CRC generation
    signal  INIT_CRC    : std_logic;
    signal  TX_ORIGINAL : std_logic;    -- select original data / crc data

begin


    process (CLK, RESETn)
        variable counter        : integer range 0 to 7 := 0;
        variable crc_counter    : integer range 0 to POLYNOMIAL'length-1 := POLYNOMIAL'length-1;
        variable first_flag     : boolean := true;
        variable last_flag      : boolean := false;
        variable abort_flag     : boolean := false;
    begin
        if (RESETn = '0') then
            fsm_state <= idle;
            TX_REG <= (others => '1');
            ACK <= '0';
            counter := 7;
            crc_counter := POLYNOMIAL'length-1;
            first_flag := true;  last_flag := false;  abort_flag := false;
            TX_SOF <= '0';  TX_EOF <= '0';  TX_ABORT <= '0';
            INIT_CRC <= '1';  TX_ORIGINAL <= '1';
        elsif (rising_edge(CLK)) then
            if (TXRESET = '1') then
                fsm_state <= idle;
                TX_REG <= (others => '1');
                ACK <= '0';
                counter := 7;
                crc_counter := POLYNOMIAL'length-1;
                first_flag := true;  last_flag := false;  abort_flag := false;
                TX_SOF <= '0';  TX_EOF <= '0';  TX_ABORT <= '0';
                INIT_CRC <= '1';  TX_ORIGINAL <= '1';
            else
                case(fsm_state) is
                when idle =>
                    ACK <= '0';
                    TX_SOF <= '0';  TX_EOF <= '0';  TX_ABORT <= '0';
                    INIT_CRC <= '1';  TX_ORIGINAL <= '1';
                    if (START_REQ = '1') then
                        fsm_state <= get_tx_data;
                    end if;
                    counter := 7;
                    crc_counter := POLYNOMIAL'length-1;
                    first_flag := true;  last_flag := false;  abort_flag := false;
                when get_tx_data =>
                    TX_REG <= DATA;
                    ACK <= '1';
                    TX_EOF <= '0';  TX_ABORT <= '0';
                    INIT_CRC <= '0';  TX_ORIGINAL <= '1';
                    fsm_state <= send_data;
                    if (first_flag = true) then
                        first_flag := false;
                        TX_SOF <= '1';
                    else
                        TX_SOF <= '0';
                    end if;
                    if (LAST = '1') then
                        last_flag := true;
                        counter := conv_integer(LAST_SIZE);
                    else
                        last_flag := false;
                        counter := 7;
                    end if;
                    if (ABORT = '1') then
                        abort_flag := true;
                        last_flag := true;
                    end if;
                when send_data =>
                    ACK <= '0';
                    INIT_CRC <= '0';  TX_ORIGINAL <= '1';
                    if (TX_ACK = '1') then
                        TX_REG <= '1' & TX_REG(7 downto 1);
                    end if;
                    if (counter = 0) then
                        if (TX_ACK = '1') then
                            TX_SOF <= '0';  TX_EOF <= '0';  TX_ABORT <= '0';
                            if (abort_flag = true) then
                                fsm_state <= idle;
                            elsif (last_flag = true) then
                                if (transparent = true) then
                                    fsm_state <= idle;
                                else
                                    fsm_state <= send_fcs;
                                end if;
                            else
                                fsm_state <= get_tx_data;
                            end if;
                        else
                            if (abort_flag = true) then
                                TX_EOF <= '1';  TX_ABORT <= '1';
                            elsif (last_flag = true and transparent = true) then
                                TX_EOF <= '1';  TX_ABORT <= '0';
                            end if;
                        end if;
                    else
                        if (TX_ACK = '1') then
                            TX_SOF <= '0';  TX_EOF <= '0';  TX_ABORT <= '0';
                            counter := counter - 1;
                         end if;
                    end if;
                when send_fcs =>
                    ACK <= '0';
                    INIT_CRC <= '0';  TX_ORIGINAL <= '0';
                    if (crc_counter = 0) then
                        if (TX_ACK = '1') then
                            TX_SOF <= '0';  TX_EOF <= '0';  TX_ABORT <= '0';
                            fsm_state <= idle;
                        else
                            TX_SOF <= '0';  TX_EOF <= '1';  TX_ABORT <= '0';
                        end if;
                    else
                        if (TX_ACK = '1') then
                            crc_counter := crc_counter - 1;
                        end if;
                    end if;
                when others =>
                    ACK <= '0';
                    TX_SOF <= '0';  TX_EOF <= '0';  TX_ABORT <= '0';
                    INIT_CRC <= '1';  TX_ORIGINAL <= '1';
                    fsm_state <= get_tx_data;
                    counter := 7;
                    crc_counter := POLYNOMIAL'length-1;
                    first_flag := true;  last_flag := false;  abort_flag := false;
                end case;
            end if;
        end if;
    end process;
    TEMP_TX_DT <= TX_REG(0);    -- lsb first


    inst_tx_frame_bitstuff: tx_frame_bitstuff
        generic map (
            share_flag  => share_flag,
            share_zero  => share_zero,
            fill_flag   => fill_flag
        )
        port map (
            CLK         => CLK,
            RESETn      => RESETn,
            TXRESET     => TXRESET,
            TXCn        => TXCn,
            TXD         => TXD,
            SOF         => TX_SOF,
            EOF         => TX_EOF,
            ABORT       => TX_ABORT,
            DATA        => TX_DATA,
            ACK         => TX_ACK
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
            ENB         => TX_ACK,
            DIN         => TEMP_TX_DT,
            DIN_AVAIL   => TX_ORIGINAL,
            DOUT        => TX_DATA,
            CRCERR      => open,
            CRC         => open
        );
end RTL;
    
      