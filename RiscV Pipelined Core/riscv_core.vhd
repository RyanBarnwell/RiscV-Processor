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
          --next_state : fsm;
          pc_in     : in  std_logic_vector(31 downto 0);
          pc_out    : out std_logic_vector(31 downto 0)
        );
      end component;
  
      component Decoder is
        port (
            instr : in std_logic_vector(31 downto 0);
            --EX_regWr : in std_logic;
            --MEM_regWr : in std_logic;
            --EX_wrRegNum : in std_logic_vector(4 downto 0);
            --MEM_wrRegNum : in std_logic_vector(4 downto 0);
            --ID_readr1 : in std_logic_vector(4 downto 0);
            --ID_readr2: in std_logic_vector(4 downto 0);
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
            --forwardA : out std_logic_vector(1 downto 0);
            --forwardB : out std_logic_vector(1 downto 0)
        );
    end component;

    --SIGNALS
    signal imem_cs_r : std_logic := '1';
    --fsm, handled in riscv_pkg
    --type fsm is (FETCH, DECODE, EXECUTE, MEMORY, WRITEBACK);
    --signal current_state : fsm;
    --signal next_state : fsm;
    --pc, always starts at 0
    signal pc_r : std_logic_vector(31 downto 0) := (others => '0');
    --used for pc input
    signal pc_in_r : std_logic_vector(31 downto 0) := (others => '0');
    --ifmt
    signal ifmt_r : fmt_type;
    --imm gen signals
    
    signal imm_out_r : std_logic_vector(31 downto 0);

    --reg sigs
    signal readr1_r : std_logic_vector(4 downto 0); --read reg 1
    signal readr2_r : std_logic_vector(4 downto 0); --read reg 2
    signal wrRegNum_r : std_logic_vector(4 downto 0); --wr register
    signal wData_r : std_logic_vector(width - 1 downto 0); --write data
    --signal wrEn_r : std_logic;
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

    -- =====================================================
    -- === pipeline signals ===
    -- ======================================================
    --ID signals
    signal ID_instruction_r : std_logic_vector(31 downto 0);
    signal ID_pc_r : std_logic_vector(31 downto 0);

    --EX signals
    signal EX_instruction_r : std_logic_vector(31 downto 0);
    signal EX_pc_r : std_logic_vector(31 downto 0);
    signal EX_ifmt_r : fmt_type;
    signal EX_opcode_r : alu_shift_opcode;
    --flags
    signal EX_ALUsrc_r : std_logic;
    signal EX_memWrite_r : std_logic;
    signal EX_memRead_r : std_logic;
    signal EX_memToReg_r : std_logic;
    signal EX_regWr_r : std_logic;
    signal EX_jalEn_r : std_logic;
    signal EX_jalrEn_r : std_logic;
    signal EX_loadFlag_r : std_logic;
    signal EX_branch_r : std_logic;
    signal EX_imm_out_r : std_logic_vector(31 downto 0);
    signal EX_rdData1_r : std_logic_vector(31 downto 0);
    signal EX_rdData2_r : std_logic_vector(31 downto 0);
    signal EX_wrRegNum_r : std_logic_vector(4 downto 0);
    signal EX_dmem_cs : std_logic;
    signal EX_dmem_wr_en : std_logic_vector(3 downto 0);
    signal EX_dmem_addr : std_logic_vector(31 downto 0);
    signal EX_dmem_wdata : std_logic_vector(31 downto 0);

    --MEM signals
    signal MEM_instruction_r : std_logic_vector(31 downto 0);
    signal MEM_pc_r : std_logic_vector(31 downto 0);
    signal MEM_ifmt_r : fmt_type;
    signal MEM_opcode_r : alu_shift_opcode;
    signal MEM_zero_r : std_logic;
    signal MEM_memWrite_r : std_logic;
    signal MEM_memRead_r : std_logic;
    signal MEM_memToReg_r : std_logic;
    signal MEM_regWr_r : std_logic;
    signal MEM_jalEn_r : std_logic;
    signal MEM_jalrEn_r : std_logic;
    signal MEM_loadFlag_r : std_logic;
    signal MEM_branch_r : std_logic;
    signal MEM_imm_out_r : std_logic_vector(31 downto 0);
    signal MEM_result_r : std_logic_vector(31 downto 0);
    signal MEM_rdData2_r : std_logic_vector(31 downto 0);
    signal MEM_wrRegNum_r : std_logic_vector(4 downto 0);
    signal MEM_dmem_cs : std_logic;
    signal MEM_dmem_wr_en : std_logic_vector(3 downto 0);
    signal MEM_dmem_addr : std_logic_vector(31 downto 0);
    signal MEM_dmem_wdata : std_logic_vector(31 downto 0);
    signal MEM_jal_return_r : std_logic_vector(31 downto 0);


    --WB signals
    signal WB_instruction_r : std_logic_vector(31 downto 0);
    signal WB_pc_r : std_logic_vector(31 downto 0);
    signal WB_ifmt_r : fmt_type;
    signal WB_opcode_r : alu_shift_opcode;
    signal WB_zero_r : std_logic;
    signal WB_memWrite_r : std_logic;
    signal WB_memRead_r : std_logic;
    signal WB_memToReg_r : std_logic;
    signal WB_regWr_r : std_logic;
    signal WB_jalEn_r : std_logic;
    signal WB_jalrEn_r : std_logic;
    signal WB_loadFlag_r : std_logic;
    signal WB_branch_r : std_logic;
    signal WB_imm_out_r : std_logic_vector(31 downto 0);
    signal WB_result_r : std_logic_vector(31 downto 0);
    signal WB_wrRegNum_r : std_logic_vector(4 downto 0);
    signal WB_wData_r : std_logic_vector(31 downto 0);
    signal WB_dmem_read_r : std_logic_vector(31 downto 0);
    signal WB_jal_return_r : std_logic_vector(31 downto 0);

    --FORWARDING
    signal forwardA_r : std_logic_vector(1 downto 0);
    signal forwardB_r : std_logic_vector(1 downto 0);

    signal forward_rdata1_r : std_logic_vector(31 downto 0);
    signal EX_storeData_r : std_logic_vector(31 downto 0);
    signal MEM_forwardB_r : std_logic_vector(1 downto 0);

    --branch
    signal squash_r : std_logic := '0';
    --use jump_en_r

    --load/use
    signal load_stall_r : std_logic;

    begin

    -- =========================================================================================================
    -- === IF SECTION ===
    -- =========================================================================================================


        --PC BLOCK
        pc1 : pc
        port map (
        clk    => clk,
        rst0   => rst0,
        pc_in  => pc_in_r,
        pc_out => pc_r
        );

        --mux to choose between +4 and branch
        pc_update: process(all)
        begin
        --keep current pc
            if load_stall_r = '1' then
                -- STALL: Hold PC
                pc_in_r <= pc_r;
            elsif jump_en_r = '1' then
                pc_in_r <= jump_target_r;
            else
                pc_in_r <= std_logic_vector(unsigned(pc_r) + 4);
            end if;
        end process;

        --IMEM BLOCK
        --push current pc into imem
        imem_addr <= pc_r;
        imem_wr_en <= (others => '0');
        imem_wdata <= (others => '0');
        --GOOD  
        --imem_cs is always 1 in pipeline, only 1 during Fetchm but only used during fetch
        imem_cs <= '1';


        -- IF/ID PIPELINE REGS
        --assign output of imem, needs to go into pipeline reg
        IF_proc : process(clk)
        begin
            if rising_edge(clk) then
                if squash_r = '1' then
                    ID_instruction_r <= (others => '0');  -- Insert NOP
                    ID_pc_r <= (others => '0');
                elsif load_stall_r = '0' then
                        -- NORMAL: Update IF/ID registers
                        ID_instruction_r <= imem_rdata;
                        ID_pc_r <= pc_r;
                else
                        -- STALL: Hold current values (do nothing)
                        -- Keeps the same instruction in ID
                end if;
            end if;
        end process;

    -- =========================================================================================================
    -- === ID SECTION ===
    -- =========================================================================================================

        --GOOD
        --read r1 and r2 are same regardless of ifmt
        readr1_r <= ID_instruction_r(19 downto 15);
        readr2_r <= ID_instruction_r(24 downto 20);
        wrRegNum_r <= ID_instruction_r(11 downto 7);

        --disable wrEn_r in this section
        --GOOD
        --Run regFile
        regFile: riscv_reg
        port map (
          clk => clk,
          rst0 => rst0,
          --Use WB writes
          wrRegEn => WB_regWr_r,
          wrRegNum => WB_wrRegNum_r,
          rdRegNum1 => readr1_r,
          rdRegNum2 => readr2_r,
          wData  => WB_wData_r,
          rdData1 => rdData1_r,
          rdData2 => rdData2_r
        );
        
        --Updates whenever instruction updates
        --ONLY NEED 1 DECODER
        decode1 : Decoder
        port map (
            --in
            instr => ID_instruction_r,
            --EX_regWr => EX_regWr_r,
            --MEM_regWr => MEM_regWr_r,
            --EX_wrRegNum => EX_wrRegNum_r,
            --MEM_wrRegNum => MEM_wrRegNum_r,
            --ID_readr1 => readr1_r,
            --ID_readr2 => readr2_r,
            --out
            ifmt => ifmt_r,
            opcode => opcode_r,
            --1 for imm, 0 for rd
            ALUsrc => ALUsrc_r,
            --not needed
            ALUsrcPC => ALUsrcPC_r,
            --outs
            memWrite => memWrite_r,
            memRead => memRead_r,
            memToReg => memToReg_r,
            regWr => regWr_r,
            jalEn => jalEn_r,
            jalrEn => jalrEn_r,
            loadFlag => loadFlag_r,
            branch => branch_r
            --forwardA => forwardA_r,
            --forwardB => forwardB_r
        );

        --GOOD
        --IMM GEN
        immg1: immediate_generator
        port map (
            --in
            instruction => ID_instruction_r,
            --out
            ifmt => ifmt_r,
            imm_out => imm_out_r
        );

        forward : process(all)
        begin
            --store read reg data across EX and MEM... DO SAME FOR rd2!!!
            if (EX_regWr_r = '1') and (EX_wrRegNum_r /= "00000") and (EX_wrRegNum_r = readr1_r) then
                forwardA_r <= "01"; -- Forward from EX stage
            elsif (MEM_regWr_r = '1') and (MEM_wrRegNum_r /= "00000") and (MEM_wrRegNum_r = readr1_r) then
                forwardA_r <= "10"; -- Forward from MEM stage
            else
                forwardA_r <= "00"; -- No forwarding, use register file
            end if;    
             --store read reg data across EX and MEM... DO SAME FOR rd2!!!
            if (EX_regWr_r = '1') and (EX_wrRegNum_r /= "00000") and (EX_wrRegNum_r = readr2_r) then
                forwardB_r <= "01"; -- Forward from EX stage
            elsif (MEM_regWr_r = '1') and (MEM_wrRegNum_r /= "00000") and (MEM_wrRegNum_r = readr2_r) then
                forwardB_r <= "10"; -- Forward from MEM stage
            else
                forwardB_r <= "00"; -- No forwarding, use register file
            end if;
        end process;

        ID_proc : process(clk)
        variable load_stall_v : std_logic := '0';
        begin
            if rising_edge(clk) then

                -- ================================
                -- Hazard Detection (before writing to EX)
                -- ================================
                --if (EX_loadFlag_r = '1') and ((EX_wrRegNum_r = readr1_r) or (EX_wrRegNum_r = readr2_r)) and (EX_wrRegNum_r /= "00000") then
                --    load_stall_v := '1';
                --else
                --    load_stall_v := '0';
                --end if;

                --if jumps set squash next instruction
                if jump_en_r = '1' or squash_r = '1' then
                    -- SQUASH: Replace instruction and control signals with NOP
                    EX_instruction_r <= (others => '0');
                    EX_pc_r <= (others => '0');
                    EX_ifmt_r <= ifmt_r;
                    EX_opcode_r <= (others => '0');
                    EX_ALUsrc_r <= '0';
                    EX_memWrite_r <= '0';
                    EX_memRead_r <= '0';
                    EX_memToReg_r <= '0';
                    EX_regWr_r <= '0';
                    EX_jalEn_r <= '0';
                    EX_jalrEn_r <= '0';
                    EX_loadFlag_r <= '0';
                    EX_branch_r <= '0';
                    EX_imm_out_r <= (others => '0');
                    EX_rdData1_r <= (others => '0');
                    EX_rdData2_r <= (others => '0');
                    EX_wrRegNum_r <= (others => '0');
--               elsif load_stall_v = '1' then
--                    -- STALL: Hold EX with NOP, freeze IF/ID in IF_proc
--                    EX_instruction_r <= (others => '0');
--                    EX_pc_r <= (others => '0');
--                    EX_ifmt_r <= ifmt_r;
--                    EX_opcode_r <= (others => '0');
--                    EX_ALUsrc_r <= '0';
--                    EX_memWrite_r <= '0';
--                    EX_memRead_r <= '0';
--                    EX_memToReg_r <= '0';
--                    EX_regWr_r <= '0';
--                    EX_jalEn_r <= '0';
--                    EX_jalrEn_r <= '0';
--                    EX_loadFlag_r <= '0';
--                    EX_branch_r <= '0';
--                    EX_imm_out_r <= (others => '0');
 --                   EX_rdData1_r <= (others => '0');
--                    EX_rdData2_r <= (others => '0');
 --                   EX_wrRegNum_r <= (others => '0');
                else
                    EX_instruction_r <= ID_instruction_r;
                    EX_pc_r <= ID_pc_r;
                    EX_ifmt_r <= ifmt_r;
                    EX_opcode_r <= opcode_r;
                    EX_ALUsrc_r <= ALUsrc_r;
                    EX_memWrite_r <= memWrite_r;
                    EX_memRead_r <= memRead_r;
                    EX_memToReg_r <= memToReg_r;
                    EX_regWr_r <= regWr_r;
                    EX_jalEn_r <= jalEn_r;
                    EX_jalrEn_r <= jalrEn_r;
                    EX_loadFlag_r <= loadFlag_r;
                    EX_branch_r <= branch_r;
                    EX_imm_out_r <= imm_out_r;
                    EX_rdData1_r <= rdData1_r;
                    EX_rdData2_r <= rdData2_r;
                    --ONLY NEEDS TO EXIST IN WRITEBACK
                    EX_wrRegNum_r <= wrRegNum_r;
                end if;
            end if;
        end process;

    -- =========================================================================================================
    -- === EX SECTION ===
    -- =========================================================================================================


            --rd1 MUX, update with ifmt_r and imm_out_r and rdData2_r
            mux_rdata1: process(EX_rdData1_r, forwardA_r, MEM_result_r, WB_result_r)
            begin
                if forwardA_r = "01" then
                    -- Forward from MEM stage (e.g., ALU result)
                    forward_rdata1_r <= result_r;
                elsif forwardA_r = "10" then
                    -- Forward from WB stage
                    forward_rdata1_r <= MEM_result_r;
                else
                    -- Use regular register read value
                    forward_rdata1_r <= EX_rdData1_r;
                end if;
            end process;

        --works
        --rd2 MUX, update with ifmt_r and imm_out_r and rdData2_r
        mux_rdata2: process(EX_ALUsrc_r, EX_imm_out_r, EX_rdData2_r, forwardB_r, MEM_result_r, WB_result_r)
            begin
                -- if immediate type put immediate from immgen in alu
                if EX_ALUsrc_r = '1' then
                    alu_imm <= EX_imm_out_r;
                --if not immediate use register
                elsif forwardB_r = "01" then
                    -- Forward from MEM stage (e.g., ALU result)
                    alu_imm <= result_r;
                elsif forwardB_r = "10" then
                    -- Forward from WB stage
                    alu_imm <= MEM_result_r;
                else
                    -- Use regular register read value
                    alu_imm <= EX_rdData2_r;
                end if;
            end process;

        --ALU
        alu1: ALU
        port map (
            a => forward_rdata1_r,
            b => alu_imm,
            alu_shift_opcode => EX_opcode_r,
            --outs
            result => alu_result_r,
            zero => zero_r
        );

        --shamt slice
        shamt_s <= to_integer(unsigned(alu_imm(4 downto 0)));
        --SHIFT
        shift1: SHIFT
        port map (
            upper => forward_rdata1_r,
            lower => EX_rdData2_r,
            shamt => shamt_s,
            alu_shift_opcode => EX_opcode_r,
            --out
            result => shift_result_r
        );

        --MUX ALU/SHIFTer
        alu_shift_select: process(all)
        variable result_v : std_logic_vector(31 downto 0);
        begin
            case EX_opcode_r is
              --when Shift
              when SHIFT_SLL | SHIFT_SRL | SHIFT_SRA =>
                result_v := shift_result_r;
              when others =>
                --when ALU
                result_v := alu_result_r;
            end case;
            result_r <= result_v;
        end process;


        store_data_forwarding : process(EX_rdData2_r, forwardB_r, MEM_result_r, WB_result_r)
            begin
                case forwardB_r is
                    when "00" => EX_storeData_r <= EX_rdData2_r;
                    when "01" => EX_storeData_r <= MEM_result_r;
                    when "10" => EX_storeData_r <= WB_result_r;
                    when others => EX_storeData_r <= (others => '0');
                end case;
            end process;


      --USE ALU result_r
      branch_proc: process(clk)
      variable jump_en_v : std_logic := '0';
      variable jalEn_v : std_logic := '0';
      variable jump_target_v : std_logic_vector(31 downto 0) := (others => '0');
      variable jal_return_v : std_logic_vector(31 downto 0) := (others => '0');
      variable branch_taken_v : std_logic := '0';
      begin
        jump_target_r <= (others => '0');
        jump_en_r <= '0';
        jump_target_v := (others => '0');
        jump_en_v := '0';
        jal_return_v := (others => '0');
        --check if branch
        if EX_branch_r = '1' then
            case EX_instruction_r(14 downto 12) is
              --BEQ
              when "000" =>
                if zero_r = '1' then
                  --ALU used for sub
                  jump_target_v := std_logic_vector(signed(EX_pc_r) + signed(EX_imm_out_r) - 4);
                  jump_en_v := '1';
                end if;
              --BNE
              when "001" =>
                if zero_r = '0' then
                  --ALU used for sub
                  jump_target_v := std_logic_vector(signed(EX_pc_r) + signed(EX_imm_out_r));
                  jump_en_v := '1';
                end if;
              --BLT
              when "100" =>
                --if zero flag is on slt returned false
                if zero_r = '0' then
                  --ALU used for slt
                  jump_target_v := std_logic_vector(signed(EX_pc_r) + signed(EX_imm_out_r));
                  jump_en_v := '1';
                end if;
              --BGE
              when "101" =>
                --if zero on slt returned falst
                if zero_r = '1'  then
                  jump_target_v := std_logic_vector(signed(EX_pc_r) + signed(EX_imm_out_r));
                  jump_en_v := '1';
                end if;
              --BLTU
              when "110" =>
                if zero_r = '0' then
                  jump_target_v := std_logic_vector(unsigned(EX_pc_r) + unsigned(EX_imm_out_r));
                  jump_en_v := '1';
                end if;
              --BGEU
              when "111" =>
                if zero_r = '1' then
                  jump_target_v := std_logic_vector(unsigned(EX_pc_r) + unsigned(EX_imm_out_r));
                  jump_en_v := '1';
                end if;
              --Do not branch if no branch
              when others =>
                jump_en_v := '0';
            end case;
          else
            if EX_jalEn_r = '1' then
              jump_en_v     := '1';
              jump_target_v := std_logic_vector(signed(EX_pc_r) + signed(EX_imm_out_r)-4);
              jal_return_v  := std_logic_vector(unsigned(EX_pc_r) + 4);
            elsif EX_jalrEn_r = '1' then
              jump_en_v     := '1';
              jump_target_v := std_logic_vector((unsigned(EX_rdData1_r) + unsigned(EX_imm_out_r)) and x"FFFFFFFE");
              jal_return_v  := std_logic_vector(unsigned(EX_pc_r) + 4);
            end if;

        end if;
        jump_target_r <= jump_target_v;
        jump_en_r <= jump_en_v;
        jal_return_r <= jal_return_v;
      end process;



        EX_proc : process(clk)
        begin
            if rising_edge(clk) then
                squash_r <= jump_en_r;
                MEM_zero_r <= zero_r;
                MEM_result_r <= result_r;
                MEM_ifmt_r <= EX_ifmt_r;
                MEM_rdData2_r <= EX_storeData_r;
                MEM_instruction_r <= EX_instruction_r;
                MEM_memWrite_r <= EX_memWrite_r;
                MEM_memRead_r <= EX_memRead_r;
                MEM_memToReg_r <= EX_memToReg_r;
                MEM_pc_r <= EX_pc_r;
                MEM_imm_out_r <= EX_imm_out_r;
                MEM_jalEn_r <= EX_jalEn_r;
                MEM_jalrEn_r <= EX_jalrEn_r;
                MEM_loadFlag_r <= EX_loadFlag_r;
                MEM_branch_r <= EX_branch_r;
                --ONLY NEED IN WB, NO FORWARDING
                MEM_wrRegNum_r <= EX_wrRegNum_r;
                MEM_regWr_r <= EX_regWr_r;
                MEM_opcode_r <= EX_opcode_r;
                MEM_jal_return_r <= jal_return_r;
                MEM_forwardB_r <= forwardB_r;
            --_read_r <= dmem_rdata ;
            end if;
        end process;

    -- =========================================================================================================
    -- === MEM SECTION ===
    -- =========================================================================================================

        --Data aligner
        dmem: process(all)
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

        dmem_cs_v := '0';
        dmem_wr_en_v := (others => '0');
        dmem_addr_v := (others => '0');
        dmem_wdata_v := (others => '0');

        --Store, only need to check memWrite
        if EX_memWrite_r = '1' then
          --ALU output, Uses ALU_ADD to find address for store word
          dmem_addr_v := result_r;
          --dmem_cs is always 1 in Memory
          dmem_cs_v := '1';
            case EX_instruction_r(14 downto 12) is
            --SB
            when "000" =>
                case result_r(1 downto 0) is
                --where to store byte
                when "00" => 
                    dmem_wr_en_v := "0001";
                    aligned_data(7 downto 0) := EX_storeData_r(7 downto 0);
                when "01" => 
                    dmem_wr_en_v := "0010";
                    aligned_data(15 downto 8) := EX_storeData_r(7 downto 0);
                when "10" => 
                    dmem_wr_en_v := "0100";
                    aligned_data(23 downto 16) := EX_storeData_r(7 downto 0);
                when "11" => 
                    dmem_wr_en_v := "1000";
                    aligned_data(31 downto 24) := EX_storeData_r(7 downto 0);
                when others => 
                    dmem_wr_en_v := (others => '0');
                end case;
                dmem_wdata_v := aligned_data;
            -- SH
            when "001" =>
                case result_r(1 downto 0) is
                when "00" =>
                    --where to store hw
                    dmem_wr_en_v := "0011";
                    --same logic as sb
                    aligned_data(15 downto 0) := EX_storeData_r(15 downto 0);
                    aligned_data(31 downto 16) := EX_storeData_r(15 downto 0);
                when "10" =>
                    --where to store
                    dmem_wr_en_v := "1100";
                    --same logic as sb
                    aligned_data(31 downto 16) := EX_storeData_r(15 downto 0);
                    aligned_data(15 downto 0) := EX_storeData_r(15 downto 0);
                when others =>
                    dmem_wr_en_v := (others => '0');
                end case;
                dmem_wdata_v := aligned_data;
            --SW
            when "010" =>
                dmem_wr_en_v  := "1111";
                dmem_wdata_v  := EX_storeData_r;
            when others =>
                dmem_wr_en_v  := (others => '0');
            end case;
        elsif EX_memRead_r = '1' then
            --load doesn't write, dmem_addr is same
            dmem_cs_v    := '1';
            dmem_wr_en_v := "0000";
            dmem_addr_v := result_r;
            dmem_wdata_v := (others => '0');
        end if;
            dmem_cs <= dmem_cs_v;
            dmem_wr_en <= dmem_wr_en_v;
            dmem_addr <= dmem_addr_v;
            if MEM_forwardB_r /= "00" then
                dmem_wdata <= MEM_rdData2_r;
            else
                dmem_wdata <= dmem_wdata_v;
            end if;
            
            dmem_read_r <= dmem_rdata;
        end process;

        --process(clk)
        --begin
        --  if rising_edge(clk) then
        --    dmem_cs <= MEM_dmem_cs;
        --    dmem_wr_en <= MEM_dmem_wr_en;
        --    dmem_addr <= MEM_dmem_addr;
        --    dmem_wdata <= MEM_dmem_wdata;
        --   dmem_read_r <= dmem_rdata ;
        --  end if;
        --end process;

        --FORWARDING
        MEM_proc : process(clk)
            begin
                if rising_edge(clk) then
                    WB_instruction_r <= MEM_instruction_r;
                    WB_pc_r <= MEM_pc_r;
                    WB_opcode_r <= MEM_opcode_r;
                    WB_zero_r <= MEM_zero_r;
                    WB_memWrite_r <= MEM_memWrite_r;
                    WB_memToReg_r <= MEM_memToReg_r;
                    WB_wrRegNum_r <= MEM_wrRegNum_r;
                    WB_regWr_r <= MEM_regWr_r;
                    WB_result_r <= MEM_result_r;
                    WB_ifmt_r <= MEM_ifmt_r;
                    WB_jalEn_r <= MEM_jalEn_r;
                    WB_jalrEn_r <= MEM_jalrEn_r;
                    WB_jal_return_r <= MEM_jal_return_r;
                    WB_imm_out_r <= MEM_imm_out_r;
                    WB_memRead_r <= MEM_memRead_r;
                    WB_dmem_read_r <= dmem_read_r;
                    WB_wrRegNum_r <= MEM_wrRegNum_r;
                end if;
        end process;

    -- =========================================================================================================
    -- === WB SECTION ===
    -- =========================================================================================================
        
        -- Writeback
        writeback_proc: process(clk, WB_result_r)
        variable load_data : std_logic_vector(31 downto 0);
        variable wrEn_v : std_logic;
        variable wData_v : std_logic_vector(31 downto 0);
        begin
            --defaults set
            --WB_regWr_r <= '0';
            WB_wData_r <= (others => '0');
            load_data := (others => '0');
            wrEn_v := '0';
            wData_v := (others => '0');

            --wrEn is on for all regs
            wrEn_v  := '1';
            case WB_ifmt_r is
            when R_TYPE =>
                --enables write, then runs 
                wData_v := WB_result_r;
            when UJ_TYPE =>
                --JAL
                if WB_jalEn_r = '1' then
                wData_v := std_logic_vector(signed(WB_jal_return_r) - 4);
                end if;
            when U_TYPE => 
                --LUI
                if WB_instruction_r(6 downto 0) = "0110111" then
                wData_v := WB_imm_out_r;
                end if;
                --AUIPC
                if WB_instruction_r(6 downto 0) = "0010111" then
                wData_v := std_logic_vector(signed(WB_pc_r) + signed(WB_imm_out_r));
                end if;
            when I_TYPE =>
                --addi
                if WB_instruction_r(6 downto 0) = "0010011" then
                  wData_v := WB_result_r;
                end if;
                --JALR
                if WB_jalrEn_r = '1' then
                  wData_v := std_logic_vector(signed(WB_jal_return_r) - 4);
                end if;

                --Load Flag
                if WB_memRead_r = '1' then
                --case for lb, lh, lw
                case WB_instruction_r(14 downto 12) is
                    --LB
                    when "000" =>
                    --loads are signed, load data is obtained from dmem_rdata and stored in bottom of load_data
                    case WB_result_r(1 downto 0) is
                        when "00" => 
                        --sign extend
                        if WB_dmem_read_r(7) = '1' then
                            --must assign slices to avoid warnings
                            load_data(7 downto 0) := WB_dmem_read_r(7 downto 0);
                            load_data(31 downto 8) := (31 downto 8 => '1');
                        else
                            load_data(31 downto 8) := (31 downto 8 => '0');
                            load_data(7 downto 0) := WB_dmem_read_r(7 downto 0);
                        end if;
                        when "01" => 
                        --sign extend
                        if dmem_read_r(15) = '1' then
                            load_data(31 downto 8) := (31 downto 8 => '1');
                            load_data(7 downto 0) := WB_dmem_read_r(15 downto 8);
                        else
                            load_data(31 downto 8) := (31 downto 8 => '0');
                            load_data(7 downto 0) := WB_dmem_read_r(15 downto 8);
                        end if;
                        when "10" => 
                        --sign extend
                        if WB_dmem_read_r(23) = '1' then
                            load_data(31 downto 8) := (31 downto 8 => '1');
                            load_data(7 downto 0) := WB_dmem_read_r(23 downto 16);
                        else
                            load_data(31 downto 8) := (31 downto 8 => '0');
                            load_data(7 downto 0) := WB_dmem_read_r(23 downto 16);
                        end if;
                        when "11" => 
                        --sign extend
                        if WB_dmem_read_r(31) = '1' then
                            load_data(31 downto 8) := (31 downto 8 => '1');
                            load_data(7 downto 0) := WB_dmem_read_r(31 downto 24);
                        else
                            load_data(31 downto 8) := (31 downto 8 => '0');
                            load_data(7 downto 0) := WB_dmem_read_r(31 downto 24);
                        end if;
                        when others => 
                        load_data := (others => '0');
                    end case;
                    --LH
                    when "001" =>
                    case WB_result_r(1 downto 0) is
                        when "00" =>
                        --sign extend
                        if WB_dmem_read_r(15) = '1' then
                            load_data(31 downto 16) := (31 downto 16 => '1');
                            load_data(15 downto 0) := WB_dmem_read_r(15 downto 0);
                        else
                            load_data(31 downto 16) := (31 downto 16 => '0');
                            load_data(15 downto 0) := WB_dmem_read_r(15 downto 0);
                        end if;
                        when "10" =>
                        --sign extend
                        if WB_dmem_read_r(31) = '1' then
                            load_data(31 downto 16) := (31 downto 16 => '1');
                            load_data(15 downto 0) := WB_dmem_read_r(31 downto 16);
                        else
                            load_data(31 downto 16) := (31 downto 16 => '0');
                            load_data(15 downto 0) := WB_dmem_read_r(31 downto 16);
                        end if;
                        when others =>
                        load_data := (others => '0');
                    end case;
                    --LW
                    when "010" =>
                    load_data := WB_dmem_read_r(31 downto 0);
                    --LBU
                    when "100" =>
                    case WB_result_r(1 downto 0) is
                        when "00" => 
                        load_data(31 downto 8) := (31 downto 8 => '0');
                        load_data(7 downto 0) := WB_dmem_read_r(7 downto 0);
                        when "01" => 
                        load_data(31 downto 8) := (31 downto 8 => '0');
                        load_data(7 downto 0) := WB_dmem_read_r(15 downto 8);
                        when "10" => 
                        load_data(31 downto 8) := (31 downto 8 => '0');
                        load_data(7 downto 0) := WB_dmem_read_r(23 downto 16);
                        when "11" => 
                        load_data(31 downto 8) := (31 downto 8 => '0');
                        load_data(7 downto 0) := WB_dmem_read_r(31 downto 24);
                        when others => 
                        load_data(7 downto 0) := (others => '0');
                    end case;
                    --LHU
                    when "101" =>
                    case WB_result_r(1 downto 0) is
                        when "00" =>
                        load_data(31 downto 16) := (31 downto 16 => '0');
                        load_data(15 downto 0) := WB_dmem_read_r(15 downto 0);
                        when "10" =>
                        load_data(31 downto 16) := (31 downto 16 => '0');
                        load_data(15 downto 0) := WB_dmem_read_r(31 downto 16);
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
            --if rising_edge(clk) then

              --sim MUX
              if WB_regWr_r = '1' then
                if WB_memToReg_r = '1' then
                    -- For loads
                    WB_wData_r <= wData_v;
                else
                    -- For ALU/immediate/JAL/LUI/AUIPC
                    WB_wData_r <= wData_v;
                end if;
            else
                WB_wData_r <= (others => '0');
              end if;
        end process;
    
        --WB_proc : process(clk)
        --    begin
        --end process;
    end architecture;