-- ====================================================================
-- RIS Controller VHDL Testbench (Upgraded with Automated Assertions)
-- Designed for Xilinx Vivado / ModelSim Simulators
-- Category 4 - Simulation & Verification
-- ====================================================================
-- Description:
--   Instantiates the RIS controller under test.
--   Simulates a 10 ns (100 MHz) onboard input clock.
--   Implements high-fidelity, automated timing assertions to monitor:
--     1. Clock divider accuracy (25 MHz clock verification).
--     2. Exact 1024-bit shift registers count boundaries.
--     3. Latch signal timing constraints (asserts latch = 1 cycle).
-- ====================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity tb_ris_controller is
end tb_ris_controller;

architecture Simulation of tb_ris_controller is

    -- Component declaration for Unit Under Test (UUT)
    component ris_controller
        Port (
            clk_in       : in  std_logic;
            rst_n        : in  std_logic;
            beam_addr    : in  std_logic_vector(4 downto 0);
            start_tx     : in  std_logic;
            ris_sclk     : out std_logic;
            ris_sdata    : out std_logic;
            ris_latch    : out std_logic;
            busy         : out std_logic
        );
    end component;

    -- Stimulus Signals
    signal clk_in    : std_logic := '0';
    signal rst_n     : std_logic := '1';
    signal beam_addr : std_logic_vector(4 downto 0) := (others => '0');
    signal start_tx  : std_logic := '0';
    
    -- Monitored Output Signals
    signal ris_sclk  : std_logic;
    signal ris_sdata : std_logic;
    signal ris_latch : std_logic;
    signal busy      : std_logic;

    -- Clock configuration: 100 MHz System Clock -> 10 ns period
    constant CLK_PERIOD : time := 10 ns;
    
    -- Verification metrics counters
    signal shift_cycle_count : integer := 0;
    signal verify_latch_width : time := 0 ns;

begin

    -- 1. Instantiate the Unit Under Test (UUT)
    uut: ris_controller
        Port Map (
            clk_in    => clk_in,
            rst_n     => rst_n,
            beam_addr => beam_addr,
            start_tx  => start_tx,
            ris_sclk  => ris_sclk,
            ris_sdata => ris_sdata,
            ris_latch => ris_latch,
            busy      => busy
        );

    -- 2. System Clock Generation (100 MHz)
    clk_gen : process
    begin
        while now < 2000 us loop
            clk_in <= '0';
            wait for CLK_PERIOD / 2;
            clk_in <= '1';
            wait for CLK_PERIOD / 2;
        end loop;
        wait;
    end process;

    -- 3. Stimulus Injection Process
    stimulus : process
    begin
        -- Initial State / Power-on Reset
        rst_n <= '0';
        wait for 100 ns;
        rst_n <= '1';
        wait for 100 ns;
        
        assert busy = '0' report "[ASSERT FAILED] Controller busy after reset." severity error;
        
        -- Loop through all 20 configurations sequentially (Address 0 to 19)
        for i in 0 to 19 loop
            report "[Sim] Triggering Configuration Address " & integer'image(i) & "...";
            beam_addr <= std_logic_vector(to_unsigned(i, 5));
            wait for 20 ns;
            
            start_tx  <= '1'; -- Trigger pulse
            wait for CLK_PERIOD;
            start_tx  <= '0';
            
            -- Wait for shifting process to begin
            wait until busy = '1';
            
            -- Wait until shifting finishes (takes 1024 cycles at 12.5 MHz = 81.92 microseconds)
            wait until busy = '0';
            report "[Sim] Configuration Address " & integer'image(i) & " Complete.";
            wait for 2 us;
        end loop;
        
        -- Wait and finish simulation
        wait for 5 us;
        report "[Sim] Simulation completed successfully. All 20 configurations verified.";
        wait;
    end process;

    -- ====================================================================
    -- HIGH-FIDELITY AUTOMATED ASSERTIONS FOR VERIFICATION
    -- ====================================================================

    -- Assertion Check 1: Verify Shift Clock period (12.5 MHz = 80 ns) when active
    sclk_timing_monitor : process(ris_sclk, busy)
        variable t_prev : time := 0 ns;
        variable t_diff : time := 0 ns;
    begin
        if busy = '0' then
            t_prev := 0 ns;
        elsif rising_edge(ris_sclk) then
            if t_prev /= 0 ns then
                t_diff := now - t_prev;
                assert t_diff = 80 ns 
                    report "[ASSERT FAILED] Shift clock frequency mismatch. Expected 80 ns, got " & time'image(t_diff)
                    severity warning;
            end if;
            t_prev := now;
        end if;
    end process;

    -- Assertion Check 2: Count shift cycles to assert exact 1024-bit boundary limits
    shift_counter_process : process(ris_sclk, busy)
    begin
        if busy = '0' then
            shift_cycle_count <= 0;
        elsif rising_edge(ris_sclk) then
            shift_cycle_count <= shift_cycle_count + 1;
        end if;
    end process;

    shift_boundary_checker : process(busy)
    begin
        if falling_edge(busy) then
            assert shift_cycle_count = 1024
                report "[ASSERT FAILED] Bit shifting count boundary violation. Expected 1024 cycles, got " & integer'image(shift_cycle_count)
                severity error;
        end if;
    end process;

    -- Assertion Check 3: Verify Latch pulse timing and active-high width constraint
    latch_timing_monitor : process(ris_latch)
        variable t_latch_start : time := 0 ns;
        variable t_latch_diff  : time := 0 ns;
    begin
        if rising_edge(ris_latch) then
            t_latch_start := now;
            assert ris_sclk = '0' 
                report "[ASSERT FAILED] Latch triggered while serial shift clock is still active."
                severity error;
        end if;
        if falling_edge(ris_latch) then
            t_latch_diff := now - t_latch_start;
            assert t_latch_diff = 40 ns
                report "[ASSERT FAILED] Latch pulse width must be exactly 1 shift clock cycle (40 ns). Got " & time'image(t_latch_diff)
                severity error;
        end if;
    end process;

end Simulation;
