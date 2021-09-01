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

-- clock devider
-- Rev.00   04/Dec./2020 created
-- (clk_freq rem devided_freq != 0) cause inaccurate in frequency
-- ((clk_freq / divide_freq) rem 2 != 0) cause inaccurate in duty

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;

entity clk_devider is
    generic (
        clk_freq        : integer := 100_000_000;
        devided_freq    : integer :=   2_048_000
    );
    port (
        CLK     : in    std_logic;
        RESETn  : in    std_logic;
        CLKDEV  : out   std_logic
    );
end clk_devider;

architecture RTL of clk_devider is

begin

    process (CLK, RESETn)
        variable counter    : integer range 0 to clk_freq / devided_freq - 1 := clk_freq / devided_freq - 1;
    begin
        if (RESETn = '0') then
            CLKDEV <= '0';
            counter := clk_freq / devided_freq - 1;
        elsif (rising_edge(CLK)) then
            case (counter) is
            when 0 =>
                CLKDEV <= '0';
            when clk_freq / devided_freq / 2 =>
                CLKDEV <= '1';
            when others =>
                null;
            end case;
            if (counter = 0) then
                counter := clk_freq / devided_freq - 1;
            else
                counter := counter - 1;
            end if;
        end if;
    end process;


end RTL;
