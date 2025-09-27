library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.riscv_pkg.all;

entity ALU is
    port (
      a : in std_logic_vector(31 downto 0);
      b : in std_logic_vector(31 downto 0);
      alu_shift_opcode        : in alu_shift_opcode;
      result     : out std_logic_vector(31 downto 0);
      zero : out std_logic
    );
end entity ALU;

architecture behavior of ALU is
    --signal a_signed : signed(31 downto 0);
    --signal b_signed : signed(31 downto 0);
    --signal a_unsigned : unsigned(31 downto 0);
    --signal b_unsigned : unsigned(31 downto 0);
    --signal result_signed      : signed(31 downto 0);
    begin
        --a_signed <= signed(a);
        --b_signed <= signed(b);
        --a_unsigned <= unsigned(a);
        --b_unsigned <= unsigned(b);
        --process(a_signed, b_signed, a_unsigned, b_unsigned, alu_shift_opcode)
	process(a, b, alu_shift_opcode)
        variable a_signed   : signed(31 downto 0);
        variable b_signed   : signed(31 downto 0);
        variable a_unsigned : unsigned(31 downto 0);
        variable b_unsigned : unsigned(31 downto 0);
	variable result_signed   : signed(31 downto 0);
        begin
	    a_signed   := signed(a);
        b_signed   := signed(b);
        a_unsigned := unsigned(a);
        b_unsigned := unsigned(b);
        result_signed := (others => '0');
        case alu_shift_opcode is
            when ALU_ADD =>
                result_signed := a_signed + b_signed;
            when ALU_SUB =>
                result_signed := a_signed - b_signed;
            when ALU_SLT =>
                if(a_signed < b_signed) then
                    --need 31 downto 1 in order to have right size
                    --result_signed <= (others => '0');
                    --result_signed(0) <= '1';
                    result_signed := (31 downto 1 => '0', 0 => '1');
                else
                    result_signed := (others => '0');
                end if;
            when ALU_SLTU =>
                if(a_unsigned < b_unsigned) then
                    --need 31 downto 1 in order to have right size
                    --result_signed <= (others => '0');
                    --result_signed(0) <= '1';
                    result_signed := (31 downto 1 => '0', 0 => '1');
                else
                    result_signed := (others => '0');
                end if;
            when ALU_AND =>
                result_signed := a_signed and b_signed;
            when ALU_OR =>
                result_signed := a_signed or b_signed;
            when ALU_XOR =>
                result_signed := a_signed xor b_signed;
            --catch all else
            when others =>
                result_signed := (others => '0');
        end case;
        result <= std_logic_vector(result_signed);

        --zero flag check, flag on when zero
        if result_signed = 0 then
            zero <= '1';
        else
            zero <= '0';
        end if;
        end process;
end architecture behavior;