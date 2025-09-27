library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.riscv_pkg.all;

--upper and lower inputs determined by intr decoder, external component
entity SHIFT is
    port (
      upper : in std_logic_vector(31 downto 0);
      lower : in std_logic_vector(31 downto 0);
      shamt : integer range 0 to 31;
      alu_shift_opcode        : in alu_shift_opcode;
      result     : out std_logic_vector(31 downto 0)
    );
end entity SHIFT;

--upper and lower significance depends on instr.  One will be 0s before Shifter and one will be the 32 bit input, determined by external logic
architecture behavior of SHIFT is
    signal funnel : std_logic_vector(63 downto 0);
    --shamt is shift amount
    begin
        process(upper, lower, shamt, alu_shift_opcode)
            variable funnel_loc : std_logic_vector(63 downto 0);
            variable temp_result : std_logic_vector(31 downto 0);
        begin
            --Default
            temp_result := (others => '0');

            case alu_shift_opcode is
                --for SLL upper is important
                --for SLL take 32 - shamt
                when SHIFT_SLL =>
                    funnel_loc := upper & (31 downto 0 => '0');
                    --temp_result := funnel_loc(63 - shamt downto 32 - shamt);
                --For SRL lower is important
                when SHIFT_SRL =>
                    --take all 0s and lower
                    funnel_loc := (63 downto 32 => '0') & lower;
                    --temp_result := funnel_loc(31 + shamt downto shamt);
                --dependent on negative, if negative upper is all 1s, all handled in instr decoder
                when SHIFT_SRA =>
                    --need to check significant bit
                    if lower(31) = '1' then
                        --set upper to all 1s
                        funnel_loc := (63 downto 32 => '1') & lower;
                    else
                        --set upper to 1s
                        funnel_loc := (63 downto 32 => '0') & lower;
                    end if;
                    --temp_result := funnel_loc(31 + shamt downto shamt);
                when others =>
                    --temp_result := (others => '0');
            end case;
                --result <= temp_result;

            --need case to manually assign shifts based on shamt?
            case alu_shift_opcode is
                when SHIFT_SLL =>
                    case shamt is
                        when 0  => temp_result := funnel_loc(63 downto 32);
                        when 1  => temp_result := funnel_loc(62 downto 31);
                        when 2  => temp_result := funnel_loc(61 downto 30);
                        when 3  => temp_result := funnel_loc(60 downto 29);
                        when 4  => temp_result := funnel_loc(59 downto 28);
                        when 5  => temp_result := funnel_loc(58 downto 27);
                        when 6  => temp_result := funnel_loc(57 downto 26);
                        when 7  => temp_result := funnel_loc(56 downto 25);
                        when 8  => temp_result := funnel_loc(55 downto 24);
                        when 9  => temp_result := funnel_loc(54 downto 23);
                        when 10 => temp_result := funnel_loc(53 downto 22);
                        when 11 => temp_result := funnel_loc(52 downto 21);
                        when 12 => temp_result := funnel_loc(51 downto 20);
                        when 13 => temp_result := funnel_loc(50 downto 19);
                        when 14 => temp_result := funnel_loc(49 downto 18);
                        when 15 => temp_result := funnel_loc(48 downto 17);
                        when 16 => temp_result := funnel_loc(47 downto 16);
                        when 17 => temp_result := funnel_loc(46 downto 15);
                        when 18 => temp_result := funnel_loc(45 downto 14);
                        when 19 => temp_result := funnel_loc(44 downto 13);
                        when 20 => temp_result := funnel_loc(43 downto 12);
                        when 21 => temp_result := funnel_loc(42 downto 11);
                        when 22 => temp_result := funnel_loc(41 downto 10);
                        when 23 => temp_result := funnel_loc(40 downto 9);
                        when 24 => temp_result := funnel_loc(39 downto 8);
                        when 25 => temp_result := funnel_loc(38 downto 7);
                        when 26 => temp_result := funnel_loc(37 downto 6);
                        when 27 => temp_result := funnel_loc(36 downto 5);
                        when 28 => temp_result := funnel_loc(35 downto 4);
                        when 29 => temp_result := funnel_loc(34 downto 3);
                        when 30 => temp_result := funnel_loc(33 downto 2);
                        when 31 => temp_result := funnel_loc(32 downto 1);
                        when others => temp_result := (others => '0');
                    end case;
    
                when SHIFT_SRL | SHIFT_SRA =>
                    case shamt is
                        when 0  => temp_result := funnel_loc(31 downto 0);
                        when 1  => temp_result := funnel_loc(32 downto 1);
                        when 2  => temp_result := funnel_loc(33 downto 2);
                        when 3  => temp_result := funnel_loc(34 downto 3);
                        when 4  => temp_result := funnel_loc(35 downto 4);
                        when 5  => temp_result := funnel_loc(36 downto 5);
                        when 6  => temp_result := funnel_loc(37 downto 6);
                        when 7  => temp_result := funnel_loc(38 downto 7);
                        when 8  => temp_result := funnel_loc(39 downto 8);
                        when 9  => temp_result := funnel_loc(40 downto 9);
                        when 10 => temp_result := funnel_loc(41 downto 10);
                        when 11 => temp_result := funnel_loc(42 downto 11);
                        when 12 => temp_result := funnel_loc(43 downto 12);
                        when 13 => temp_result := funnel_loc(44 downto 13);
                        when 14 => temp_result := funnel_loc(45 downto 14);
                        when 15 => temp_result := funnel_loc(46 downto 15);
                        when 16 => temp_result := funnel_loc(47 downto 16);
                        when 17 => temp_result := funnel_loc(48 downto 17);
                        when 18 => temp_result := funnel_loc(49 downto 18);
                        when 19 => temp_result := funnel_loc(50 downto 19);
                        when 20 => temp_result := funnel_loc(51 downto 20);
                        when 21 => temp_result := funnel_loc(52 downto 21);
                        when 22 => temp_result := funnel_loc(53 downto 22);
                        when 23 => temp_result := funnel_loc(54 downto 23);
                        when 24 => temp_result := funnel_loc(55 downto 24);
                        when 25 => temp_result := funnel_loc(56 downto 25);
                        when 26 => temp_result := funnel_loc(57 downto 26);
                        when 27 => temp_result := funnel_loc(58 downto 27);
                        when 28 => temp_result := funnel_loc(59 downto 28);
                        when 29 => temp_result := funnel_loc(60 downto 29);
                        when 30 => temp_result := funnel_loc(61 downto 30);
                        when 31 => temp_result := funnel_loc(62 downto 31);
                        when others => temp_result := (others => '0');
                    end case;
    
                when others =>
                    temp_result := (others => '0');
            end case;
            result <= temp_result;
        end process;
end architecture;