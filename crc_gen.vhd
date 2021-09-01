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

-- CRC generator/checker
-- Rev.00   03/Dec./2020 created
-- ENB is for shift crc register according to bit stream timing.
-- At least 1 clk period, INIT_CRC must be '1' before calculating, must be '0' during calculating.
-- DIN_AVAIL must be '1' during caluculating, must be '0' during putting crc out to DOUT at generating.
-- DOUT outputs DIN when DIN_AVAIL = '1', output CRC when DIN_AVAIL = '0'.
-- When last DIN shifted in, CRC shows parallel crc data.
-- Contimue DIN_AVAIL = '1' and put received crc sequence into DIN, then CCRCERR shows error after last bit of CRC is put in.

library ieee;
use ieee.std_logic_1164.all;

entity crc_gen is
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
end crc_gen;

architecture RTL of crc_gen is

    -- linear feedback shift register
    signal  LFSR            : std_logic_vector(POLYNOMIAL'high downto POLYNOMIAL'low);
    signal  feedback        : std_logic;
    signal  expected_crc    : std_logic_vector(POLYNOMIAL'high downto POLYNOMIAL'low);

begin

    feedback <= LFSR(POLYNOMIAL'high) xor DIN when (DIN_AVAIL = '1') else '0';

    process (CLK, RESETn)
    begin
        if (RESETn = '0') then
            LFSR <= (others => '1');
        elsif (rising_edge(CLK)) then
            if (INIT_CRC = '1') then
                LFSR <= (others => '1');
            elsif (ENB = '1') then
                for i in POLYNOMIAL'low to POLYNOMIAL'high loop
                    if (i = POLYNOMIAL'low) then
                        LFSR(i) <= feedback;
                    else
                        LFSR(i) <= (feedback and POLYNOMIAL(i)) xor (LFSR(i-1));
                    end if;
                end loop;
            end if;
        end if;
    end process;

    CRC <= LFSR;
    DOUT <= DIN when (DIN_AVAIL = '1') else not LFSR(POLYNOMIAL'high) when (invert_crc = true) else LFSR(POLYNOMIAL'high);

    -- caluculate correct CRC at inverted FCS
    process
        variable    temp_crc    : std_logic_vector(POLYNOMIAL'high downto POLYNOMIAL'low) := (others => '1');
        variable    temp_fb     : std_logic;
    begin
        for j in 0 to POLYNOMIAL'length - 1 loop
            temp_fb := temp_crc(POLYNOMIAL'high);
            for i in POLYNOMIAL'high downto POLYNOMIAL'low loop
                if (i = POLYNOMIAL'low) then
                    temp_crc(i) := temp_fb;
                else
                    temp_crc(i) := (temp_fb and POLYNOMIAL(i)) xor temp_crc(i-1);
                end if;
            end loop;
        end loop;
        if (invert_crc = true) then
            expected_crc <= temp_crc;
        else
            expected_crc <= (others => '0');
        end if;
        wait;
    end process;
    CRCERR <= '0' when (LFSR = expected_crc) else '1';

end RTL;

