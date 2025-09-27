library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.std_logic_textio.all;

entity riscv_reg is
    Generic (
        width : integer := 32
    );
    port (
        clk : in std_logic;
        rst0 : in std_logic;  -- Active low reset
        wrRegEn : in std_logic;
        wrRegNum : in std_logic_vector(4 downto 0);
        rdRegNum1 : in std_logic_vector(4 downto 0);
        rdRegNum2 : in std_logic_vector(4 downto 0);
        wData : in std_logic_vector(width - 1 downto 0);
        rdData1 : out std_logic_vector(width - 1 downto 0);
        rdData2 : out std_logic_vector(width - 1 downto 0)
    );
end entity riscv_reg;

architecture rtl of riscv_reg is
    type regArray is array(0 to 31) of std_logic_vector(width - 1 downto 0);
    signal regs_r : regArray := (others => (others => '0'));
begin
    -- Register write process with reset
    regWrite: process(clk) is
        variable wrRegNum_v: integer;
    begin
        wrRegNum_v := to_integer(unsigned(wrRegNum));
        if (rst0 = '0') then
            -- Asynchronous reset
            regs_r <= (others => (others => '0'));
        elsif (rising_edge(clk)) then
            -- Only write if write enable is active and not writing to register 0
            if (wrRegEn = '1') then
                if (wrRegNum_v /= 0) then
                    regs_r(wrRegNum_v) <= wData;
                end if;
            end if;
        end if;
    end process regWrite;
    
    -- Read port 1
    read1: process(rdRegNum1, regs_r) is
        variable rdRegNum_v: integer;
    begin
        rdRegNum_v := to_integer(unsigned(rdRegNum1));
        -- Register 0 is hardwired to 0
        if (rdRegNum_v = 0) then
            rdData1 <= (others => '0');
        else
            rdData1 <= regs_r(rdRegNum_v);
        end if;
    end process read1;

    -- Read port 2
    read2: process(rdRegNum2, regs_r) is
        variable rdRegNum_v: integer;
    begin
        rdRegNum_v := to_integer(unsigned(rdRegNum2));
        -- Register 0 is hardwired to 0
        if (rdRegNum_v = 0) then
            rdData2 <= (others => '0');
        else
            rdData2 <= regs_r(rdRegNum_v);
        end if;
    end process read2;
end architecture rtl;