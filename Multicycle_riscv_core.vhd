library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use work.riscv_pkg.all;
use ieee.std_logic_textio.all;

entity riscv_core is
    port(
      rst0               :  in std_logic;
      clk                :  in std_logic;

      -- Instruction memory interface
      imem_cs            : out std_logic;
      imem_wr_en         : out std_logic_vector(3 downto 0);
      imem_addr          : out std_logic_vector(31 downto 0);
      imem_wdata         : out std_logic_vector(31 downto 0);
      imem_rdata         :  in std_logic_vector(31 downto 0);

      -- Data memory interface
      dmem_cs            : out std_logic;
      dmem_wr_en         : out std_logic_vector(3 downto 0);
      dmem_addr          : out std_logic_vector(31 downto 0);
      dmem_wdata         : out std_logic_vector(31 downto 0);
      dmem_rdata         :  in std_logic_vector(31 downto 0)
    );
end riscv_core;

architecture riscv of riscv_core is
  constant width : integer := 32;
    --components
    component ALU is
        port (
          a : in std_logic_vector(31 downto 0);
          b : in std_logic_vector(31 downto 0);
          alu_shift_opcode        : in alu_shift_opcode;
          result     : out std_logic_vector(31 downto 0);
          zero : out std_logic
        );
    end component;
    component SHIFT is
        port (
          upper : in std_logic_vector(31 downto 0);
          lower : in std_logic_vector(31 downto 0);
          shamt : integer range 0 to 31;
          alu_shift_opcode        : in alu_shift_opcode;
          result     : out std_logic_vector(31 downto 0)
        );
    end component;
    component riscv_reg is
        Generic (
            width : integer := 32
        );
        port (
            clk : in std_logic;
            rst0 : in std_logic;
            wrRegEn : in std_logic;
            wrRegNum : in std_logic_vector(4 downto 0);
            rdRegNum1 : in std_logic_vector(4 downto 0);
            rdRegNum2 : in std_logic_vector(4 downto 0);
            wData : in std_logic_vector(width - 1 downto 0);
            rdData1 : out std_logic_vector(width - 1 downto 0);
            rdData2 : out std_logic_vector(width - 1 downto 0)
        );
    end component;
    component immediate_generator is
        port (
          instruction : in std_logic_vector(31 downto 0);
          ifmt        : in fmt_type;
          imm_out     : out std_logic_vector(31 downto 0)
        );
    end component;
    component pc is
      port (
        clk       : in  std_logic;
        rst0      : in  std_logic;
        next_state : fsm;
        pc_in     : in  std_logic_vector(31 downto 0);
        pc_out    : out std_logic_vector(31 downto 0)
      );
    end component;

    component Decoder is
      port (
          instr : in std_logic_vector(31 downto 0);
          ifmt : out fmt_type;
          opcode : out alu_shift_opcode;
          memWrite : out std_logic;
          memRead : out std_logic;
          ALUsrc : out std_logic; --1 for imm, 0 for rdData2
          ALUsrcPC : out std_logic;
          memToReg : out std_logic;
          regWr : out std_logic;
          jalEn : out std_logic;
          jalrEn : out std_logic;
          loadFlag : out std_logic;
          branch : out std_logic
      );
  end component;

    signal imem_cs_r : std_logic := '1';
    --fsm, handled in riscv_pkg
    --type fsm is (FETCH, DECODE, EXECUTE, MEMORY, WRITEBACK);
    signal current_state : fsm;
    signal next_state : fsm;
    --pc, always starts at 0
    signal pc_r : std_logic_vector(31 downto 0) := (others => '0');
    --used for pc input
    signal pc_in_r : std_logic_vector(31 downto 0) := (others => '0');
    --ifmt
    signal ifmt_r : fmt_type;
    --imm gen signals
    signal instruction_r : std_logic_vector(31 downto 0);
    signal imm_out_r : std_logic_vector(31 downto 0);

    --reg sigs
    signal readr1_r : std_logic_vector(4 downto 0); --read reg 1
    signal readr2_r : std_logic_vector(4 downto 0); --read reg 2
    signal wrRegNum_r : std_logic_vector(4 downto 0); --wr en
    signal wData_r : std_logic_vector(width - 1 downto 0); --write data
    signal wrEn_r : std_logic;
    signal rdData1_r : std_logic_vector(width -1 downto 0);
    signal rdData2_r : std_logic_vector(width -1 downto 0);

    --immediate input for alu
    signal alu_imm : std_logic_vector(width - 1 downto 0);
    --
    signal opcode_r : alu_shift_opcode;

    signal alu_result_r : std_logic_vector(31 downto 0);
    signal shift_result_r : std_logic_vector(31 downto 0);
    signal result_r : std_logic_vector(31 downto 0);

    --pcupdate
    signal jump_en_r : std_logic;
    signal jump_target_r: std_logic_vector(31 downto 0);
    signal jal_return_r: std_logic_vector(31 downto 0);

    --mem signals
    signal mem_result_r      : std_logic_vector(31 downto 0);
    signal mem_rdData2_r     : std_logic_vector(31 downto 0);
    signal mem_instruction_r : std_logic_vector(31 downto 0);
    signal mem_ifmt_r        : fmt_type;

    signal shamt_s : integer range 0 to 31;

    --decoder sigs
    signal ALUsrc_r :  std_logic;--1 for imm, 0 for rdData2
    signal ALUsrcPC_r : std_logic; --1 for PC
    signal memWrite_r : std_logic;
    signal memRead_r : std_logic;
    signal memToReg_r :  std_logic;
    signal regWr_r : std_logic;
    signal jalEn_r : std_logic;
    signal jalrEn_r : std_logic;
    signal loadFlag_r : std_logic;
    signal branch_r : std_logic;

    signal zero_r : std_logic;
    signal dmem_read_r : std_logic_vector(31 downto 0);

    signal alu_in1 : std_logic_vector(31 downto 0);


    begin

      --runs when rst0 or clk changes
      seq_logic: process(clk, rst0) is
        begin
          if rising_edge(clk) then
            if rst0 = '0' then
              current_state <= RESET;
            else
              current_state <= next_state;
            end if;
          end if;
        end process;

      --Always runs after seq_logic
      comb_logic: process(current_state)
        variable next_state_v: fsm;
        begin
          -- Default is to stay in same state
          next_state_v := current_state;
          case current_state is
          ---------------------
            when RESET => 
              next_state_v := FETCH;
            when FETCH =>
              next_state_v := DECODE;
              ---------------------
            when DECODE =>
              next_state_v := EXECUTE;
              ---------------------
            when EXECUTE =>
              --Memory only happens for store and load instructions
              if ifmt_r = S_TYPE or instruction_r(6 downto 0) = "0000011" then
                -- Store or Load -> go to MEMORY
                next_state_v := MEMORY;
              else
                -- All others skip MEMORY
                next_state_v := WRITEBACK;
              end if;
            -----------------
            when MEMORY =>
              --s_type skips writeback
              if ifmt_r /= S_TYPE then
                next_state_v := WRITEBACK;
              else
                next_state_v := FETCH;
              end if;
            when WRITEBACK =>
              next_state_v := FETCH;
            when others =>
              next_state_v := FETCH;
          end case;
          next_state <= next_state_v;
        end process comb_logic;


      --GOOD
      --PC BLOCK
      pc1 : pc
        port map (
        clk    => clk,
        rst0   => rst0,
        next_state => next_state,
        pc_in  => pc_in_r,
        pc_out => pc_r
      );

      --pc gets pushed into imem
      --GOOD
      --IMEM BLOCK
      --push current pc into imem
      imem_addr <= pc_r;
      imem_wr_en <= (others => '0');
      imem_wdata <= (others => '0');
      --GOOD  
      --imem_cs <= imem_cs_r;
      imem_cs <= '1' when current_state = FETCH else '0';
      --assign output of imem
      instruction_r <= imem_rdata;

      --GOOD
      --read r1 and r2 are same regardless of ifmt
      readr1_r <= instruction_r(19 downto 15);
      readr2_r <= instruction_r(24 downto 20);
      wrRegNum_r <= instruction_r(11 downto 7);


      --GOOD
      --Run regFile
      regFile: riscv_reg
      port map (
        clk => clk,
        rst0 => rst0,
        wrRegEn => wrEn_r,
        wrRegNum => wrRegNum_r,
        rdRegNum1 => readr1_r,
        rdRegNum2 => readr2_r,
        wData  => wData_r,
        rdData1 => rdData1_r,
        rdData2 => rdData2_r
      );

      --DECODE SECTION, SHOULD WORK
      --Updates whenever instruction updates
      --ONLY NEED 1 DECODER
      decode1 : Decoder
      port map (
            instr => instruction_r,
            ifmt => ifmt_r,
            opcode => opcode_r,
            --1 for imm, 0 for rd
            ALUsrc => ALUsrc_r,
            ALUsrcPC => ALUsrcPC_r,
            memWrite => memWrite_r,
            memRead => memRead_r,
            memToReg => memToReg_r,
            regWr => regWr_r,
            jalEn => jalEn_r,
            jalrEn => jalrEn_r,
            loadFlag => loadFlag_r,
            branch => branch_r
      );

      --GOOD
      --IMM GEN
      immg1: immediate_generator
      port map (
          instruction => instruction_r,
          ifmt => ifmt_r,
          imm_out => imm_out_r
      );

      --works
      --rd2 MUX, update with ifmt_r and imm_out_r and rdData2_r
      mux_rdata2: process(ifmt_r, imm_out_r, rdData2_r)
        begin
          -- if immediate type put immediate from immgen in alu
          if ALUsrc_r = '1' then
            alu_imm <= imm_out_r;
          --if not immediate use register
          else
            alu_imm <= rdData2_r;
          end if;
        end process;

      -- need to choose between pc and reg
      --mux_rdata1: process(ifmt_r, pc_r, rdData1_r)
      --begin
        -- if flag use PC
      --  if ALUsrcPC_r = '1' then
          --pc_r should be current pc
      --    alu_in1 <= pc_r;
        --if not PC use register
      --  else
      --    alu_in1 <= rdData1_r;
      --  end if;
      --end process;


      --ALU
      alu1: ALU
      port map (
        a => rdData1_r,
        b => alu_imm,
        alu_shift_opcode => opcode_r,
        result => alu_result_r,
        zero => zero_r
      );

      --shamt slice
      shamt_s <= to_integer(unsigned(alu_imm(4 downto 0)));
      --SHIFT
      shift1: SHIFT
        port map (
          upper => rdData1_r,
          lower => rdData2_r,
          shamt => shamt_s,
          alu_shift_opcode => opcode_r,
          result => shift_result_r
        );

      --select ALU/SHIFTer
      --alu_shift_select: process(opcode_r, alu_result_r, shift_result_r)
      --Fix to not be latch
      alu_shift_select: process(clk)
      begin
            case opcode_r is
              --when Shift
              when SHIFT_SLL | SHIFT_SRL | SHIFT_SRA =>
                result_r <= shift_result_r;
              when others =>
                --when ALU
                result_r <= alu_result_r;
            end case;
      end process;

      --Update signals for data alignment
      memregs: process(clk)
      begin
          if current_state = EXECUTE then
            mem_result_r      <= result_r;
            mem_rdData2_r     <= rdData2_r;
            mem_instruction_r <= instruction_r;
            mem_ifmt_r        <= ifmt_r;
          end if;
      end process;



    --Data aligner
    dmem: process(clk, result_r, mem_rdData2_r, current_state)
      --need to do this to make sure synthesis works.  Original Idea was to use signals sequentially, but that might cause problems?
      variable aligned_data : std_logic_vector(31 downto 0);
      --use variables to speed up
      variable dmem_cs_v : std_logic;
      variable dmem_wr_en_v : std_logic_vector(3 downto 0);
      variable dmem_addr_v : std_logic_vector(31 downto 0);
      variable dmem_wdata_v : std_logic_vector(31 downto 0);
    begin
      --defaults
      aligned_data := (others => '0');
      dmem_cs <= '0';
      dmem_wr_en <= (others => '0');
      dmem_addr <= (others => '0');
      dmem_wdata <= (others => '0');

      --ALU output, Uses ALU_ADD to find address for store word
      dmem_addr_v := result_r;
      --dmem_cs is always 1 in Memory
      dmem_cs_v := '1';

      --Store, only need to check memWrite
      if memWrite_r = '1' then
        case instruction_r(14 downto 12) is
          --SB
          when "000" =>
            case mem_result_r(1 downto 0) is
              --where to store byte
              when "00" => 
                dmem_wr_en_v := "0001";
                aligned_data(7 downto 0) := mem_rdData2_r(7 downto 0);
              when "01" => 
                dmem_wr_en_v := "0010";
                aligned_data(15 downto 8) := mem_rdData2_r(7 downto 0);
              when "10" => 
                dmem_wr_en_v := "0100";
                aligned_data(23 downto 16) := mem_rdData2_r(7 downto 0);
              when "11" => 
                dmem_wr_en_v := "1000";
                aligned_data(31 downto 24) := mem_rdData2_r(7 downto 0);
              when others => 
                dmem_wr_en_v := (others => '0');
            end case;
            dmem_wdata_v := aligned_data;
          -- SH
          when "001" =>
            case mem_result_r(1 downto 0) is
              when "00" =>
                --where to store hw
                dmem_wr_en_v := "0011";
                --same logic as sb
                aligned_data(15 downto 0) := mem_rdData2_r(15 downto 0);
              when "10" =>
                --where to store
                dmem_wr_en_v := "1100";
                --same logic as sb
                aligned_data(31 downto 16) := mem_rdData2_r(15 downto 0);
              when others =>
                dmem_wr_en_v := (others => '0');
            end case;
            dmem_wdata_v := aligned_data;
          --SW
          when "010" =>
            dmem_wr_en_v  := "1111";
            dmem_wdata_v  := mem_rdData2_r;
          when others =>
            dmem_wr_en_v  := (others => '0');
        end case;
      elsif memRead_r = '1' then
        --load doesn't write, dmem_addr is same
          dmem_cs_v    := '1';
          dmem_wr_en_v := "0000";
          dmem_wdata_v := (others => '0');
      end if;
        --if current state is memory do memory write for store and read for load
        if current_state = MEMORY then
          dmem_cs <= dmem_cs_v;
          dmem_wr_en <= dmem_wr_en_v;
          dmem_addr <= dmem_addr_v;
          dmem_wdata <= dmem_wdata_v;
          if rising_edge(clk) then
            dmem_read_r <= dmem_rdata;
          end if;
        end if;
    end process;

    --writeback_comb: process(result_r, jal_return_r, imm_out_r, )
    -- Writeback
    writeback_proc: process(clk, result_r)
        variable load_data : std_logic_vector(31 downto 0);
        variable wrEn_v : std_logic;
        variable wData_v : std_logic_vector(31 downto 0);
      begin
        --defaults set
        wrEn_r <= '0';
        wData_r <= (others => '0');
        load_data := (others => '0');

        --wrEn is on for all regs
        wrEn_v  := '1';
        case ifmt_r is
          when R_TYPE =>
            --enables write, then runs 
            wData_v := result_r;
          when UJ_TYPE =>
            --JAL
            if jalEn_r = '1' then
              wData_v := jal_return_r;
            end if;
          when U_TYPE => 
            --LUI
            if instruction_r(6 downto 0) = "0110111" then
              wData_v := imm_out_r;
            end if;
            --AUIPC
            if instruction_r(6 downto 0) = "0010111" then
              wData_v := std_logic_vector(signed(pc_r) + signed(imm_out_r));
            end if;
          when I_TYPE =>
            --addi
            if instruction_r(6 downto 0) = "0010011" then
              wData_v := result_r;
            end if;
            --JALR
            if jalrEn_r = '1' then
              wData_v := jal_return_r;
            end if;

            --Load Flag
            if memRead_r = '1' then
              --case for lb, lh, lw
              case instruction_r(14 downto 12) is
                --LB
                when "000" =>
                  --loads are signed, load data is obtained from dmem_rdata and stored in bottom of load_data
                  case result_r(1 downto 0) is
                    when "00" => 
                      --sign extend
                      if dmem_read_r(7) = '1' then
                        --must assign slices to avoid warnings
                        load_data(7 downto 0) := dmem_read_r(7 downto 0);
                        load_data(31 downto 8) := (31 downto 8 => '1');
                      else
                        load_data(31 downto 8) := (31 downto 8 => '0');
                        load_data(7 downto 0) := dmem_read_r(7 downto 0);
                      end if;
                    when "01" => 
                      --sign extend
                      if dmem_read_r(15) = '1' then
                        load_data(31 downto 8) := (31 downto 8 => '1');
                        load_data(7 downto 0) := dmem_read_r(15 downto 8);
                      else
                        load_data(31 downto 8) := (31 downto 8 => '0');
                        load_data(7 downto 0) := dmem_read_r(15 downto 8);
                      end if;
                    when "10" => 
                      --sign extend
                      if dmem_read_r(23) = '1' then
                        load_data(31 downto 8) := (31 downto 8 => '1');
                        load_data(7 downto 0) := dmem_read_r(23 downto 16);
                      else
                        load_data(31 downto 8) := (31 downto 8 => '0');
                        load_data(7 downto 0) := dmem_read_r(23 downto 16);
                      end if;
                    when "11" => 
                      --sign extend
                      if dmem_read_r(31) = '1' then
                        load_data(31 downto 8) := (31 downto 8 => '1');
                        load_data(7 downto 0) := dmem_read_r(31 downto 24);
                      else
                        load_data(31 downto 8) := (31 downto 8 => '0');
                        load_data(7 downto 0) := dmem_read_r(31 downto 24);
                      end if;
                    when others => 
                      load_data := (others => '0');
                  end case;
                --LH
                when "001" =>
                  case result_r(1 downto 0) is
                    when "00" =>
                      --sign extend
                      if dmem_read_r(15) = '1' then
                        load_data(31 downto 16) := (31 downto 16 => '1');
                        load_data(15 downto 0) := dmem_read_r(15 downto 0);
                      else
                        load_data(31 downto 16) := (31 downto 16 => '0');
                        load_data(15 downto 0) := dmem_read_r(15 downto 0);
                      end if;
                    when "10" =>
                      --sign extend
                      if dmem_read_r(31) = '1' then
                        load_data(31 downto 16) := (31 downto 16 => '1');
                        load_data(15 downto 0) := dmem_read_r(31 downto 16);
                      else
                        load_data(31 downto 16) := (31 downto 16 => '0');
                        load_data(15 downto 0) := dmem_read_r(31 downto 16);
                      end if;
                    when others =>
                      load_data := (others => '0');
                  end case;
                --LW
                when "010" =>
                  load_data := dmem_read_r(31 downto 0);
                --LBU
                when "100" =>
                  case result_r(1 downto 0) is
                    when "00" => 
                      load_data(31 downto 8) := (31 downto 8 => '0');
                      load_data(7 downto 0) := dmem_read_r(7 downto 0);
                    when "01" => 
                      load_data(31 downto 8) := (31 downto 8 => '0');
                      load_data(7 downto 0) := dmem_read_r(15 downto 8);
                    when "10" => 
                      load_data(31 downto 8) := (31 downto 8 => '0');
                      load_data(7 downto 0) := dmem_read_r(23 downto 16);
                    when "11" => 
                      load_data(31 downto 8) := (31 downto 8 => '0');
                      load_data(7 downto 0) := dmem_read_r(31 downto 24);
                    when others => 
                      load_data(7 downto 0) := (others => '0');
                  end case;
                --LHU
                when "101" =>
                  case result_r(1 downto 0) is
                    when "00" =>
                      load_data(31 downto 16) := (31 downto 16 => '0');
                      load_data(15 downto 0) := dmem_read_r(15 downto 0);
                    when "10" =>
                      load_data(31 downto 16) := (31 downto 16 => '0');
                      load_data(15 downto 0) := dmem_read_r(31 downto 16);
                    when others =>
                      load_data := (others => '0');
                  end case;
                when others =>
                  load_data := (others => '0');
              end case;
              wData_v := load_data;
            end if;
          when others =>
            wrEn_v := '0';
            wData_v := (others => '0');
        end case;
        --clocked for final assignment
          --fsm check
          if current_state = WRITEBACK then
            wData_r <= wData_v;
            wrEn_r <= wrEn_v;
          end if;

    end process;

      --USE ALU result_r
      branch_proc: process(clk)
      variable jump_en_v : std_logic := '0';
      variable jalEn_v : std_logic := '0';
      variable jump_target_v : std_logic_vector(31 downto 0) := (others => '0');
      variable jal_return_v : std_logic_vector(31 downto 0) := (others => '0');
      begin
        jump_target_r <= (others => '0');
        jump_en_r <= '0';
        jump_target_v := (others => '0');
        jump_en_v := '0';
        jal_return_v := (others => '0');
        --check if branch
        if current_state = EXECUTE and branch_r = '1' then
            case instruction_r(14 downto 12) is
              --BEQ
              when "000" =>
                if zero_r = '1' then
                  --ALU used for sub
                  jump_target_v := std_logic_vector(signed(pc_r) + signed(imm_out_r));
                  jump_en_v := '1';
                end if;
              --BNE
              when "001" =>
                if zero_r = '0' then
                  --ALU used for sub
                  jump_target_v := std_logic_vector(signed(pc_r) + signed(imm_out_r));
                  jump_en_v := '1';
                end if;
              --BLT
              when "100" =>
                --if zero flag is on slt returned false
                if zero_r = '0' then
                  --ALU used for slt
                  jump_target_v := std_logic_vector(signed(pc_r) + signed(imm_out_r));
                  jump_en_v := '1';
                end if;
              --BGE
              when "101" =>
                --if zero on slt returned falst
                if zero_r = '1'  then
                  jump_target_v := std_logic_vector(signed(pc_r) + signed(imm_out_r));
                  jump_en_v := '1';
                end if;
              --BLTU
              when "110" =>
                if zero_r = '0' then
                  jump_target_v := std_logic_vector(unsigned(pc_r) + unsigned(imm_out_r));
                  jump_en_v := '1';
                end if;
              --BGEU
              when "111" =>
                if zero_r = '1' then
                  jump_target_v := std_logic_vector(unsigned(pc_r) + unsigned(imm_out_r));
                  jump_en_v := '1';
                end if;
              --Do not branch if no branch
              when others =>
                jump_en_v := '0';
            end case;
          elsif current_state = EXECUTE then
            if jalEn_r = '1' then
              jump_en_v     := '1';
              jump_target_v := std_logic_vector(signed(pc_r) + signed(imm_out_r));
              jal_return_v  := std_logic_vector(unsigned(pc_r) + 4);
            elsif jalrEn_r = '1' then
              jump_en_v     := '1';
              jump_target_v := std_logic_vector((unsigned(rdData1_r) + unsigned(imm_out_r)) and x"FFFFFFFE");
              jal_return_v  := std_logic_vector(unsigned(pc_r) + 4);
            end if;

        end if;
        jump_target_r <= jump_target_v;
        jump_en_r <= jump_en_v;
        jal_return_r <= jal_return_v;
      end process;
    
      ----pc update
      pc_update: process(clk, rst0)
        begin
          if rst0 = '0' then
            pc_in_r <= (others => '0');  -- reset PC input
          else  -- if not reset proc combinationally
            if jump_en_r = '1' then
              --jump target
              pc_in_r <= jump_target_r;
            elsif current_state = FETCH then
              --standard
              pc_in_r <= std_logic_vector(unsigned(pc_r) + 4);
            end if;
          end if;
        end process;

    end architecture;