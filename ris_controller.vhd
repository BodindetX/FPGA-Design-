-- ====================================================================
-- RIS Controller HDL Module
-- Designed for Xilinx Virtex-5 ML501 Platform (XC5VLX50)
-- Category 3 - FPGA System Architecture
-- ====================================================================
-- Description:
--   Loads a 1024-bit phase configuration from preloaded Block ROM (20 configurations total).
--   Divides the 100 MHz system clock to 25 MHz for the Shift Clock (RIS_SCLK).
--   Streams the 1024 bits serially via RIS_SDATA.
--   Generates a synchronous RIS_LATCH pulse to update all 1024 elements simultaneously.
-- ====================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ris_controller is
    Port (
        clk_in       : in  std_logic;                     -- Onboard 100 MHz clock
        rst_n        : in  std_logic;                     -- Active-low synchronous reset
        beam_addr    : in  std_logic_vector(4 downto 0);  -- 5-bit address for 20 configurations (0 to 19)
        start_tx     : in  std_logic;                     -- Pulse to trigger shifting operation
        
        -- Physical RIS Interface Pins (Shift Register Interface)
        ris_sclk     : out std_logic;                     -- Shift Register Clock (25 MHz)
        ris_sdata    : out std_logic;                     -- Serial Phase Data output
        ris_latch    : out std_logic;                     -- Latch Enable pulse (simultaneous diode update)
        
        -- Status Pins
        busy         : out std_logic                      -- Asserted high during transmission
    );
end ris_controller;

architecture Behavioral of ris_controller is

    -- 20 configurations of 1024 bits each (32x32 array)
    type codebook_rom_type is array (0 to 19) of std_logic_vector(1023 downto 0);
    
    -- Pre-filled ROM configurations mapping incident and steered angles (0, 15, 30, 45, 60 deg)
    -- Initialized with high-quality phase distributions matching the MATLAB digital twin codebook
    constant codebook_rom : codebook_rom_type := (
        -- CONFIG_01 (In0 -> Out15)
        0 => x"0000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF00000000000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF000000000000000000000000",
        -- CONFIG_02 (In0 -> Out30)
        1 => x"0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF0000000000000000FFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFF000000000000000000000000FFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFFFFFFFFFF",
        -- CONFIG_03 (In0 -> Out45)
        2 => x"00000000FFFFFFFFFFFFFFFF00000000FFFFFFFF0000000000000000FFFFFFFF0000000000000000FFFFFFFF0000000000000000FFFFFFFF00000000FFFFFFFFFFFFFFFF00000000FFFFFFFFFFFFFFFF00000000FFFFFFFF0000000000000000FFFFFFFF0000000000000000FFFFFFFF00000000FFFFFFFFFFFFFFFF00000000",
        -- CONFIG_04 (In0 -> Out60)
        3 => x"00000000FFFFFFFF00000000FFFFFFFFFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF0000000000000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF0000000000000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFF00000000FFFFFFFFFFFFFFFF00000000FFFFFFFF00000000FFFFFFFF",
        -- CONFIG_05 (In15 -> Out0)
        4 => x"3C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C383C3C3C38",
        -- CONFIG_06 (In15 -> Out30)
        5 => x"3C3C3C3870F0F0F1C3C3C3C78F0F0F0E3C3C3C3870F0F0F1C3C3C3C78F0F0F0E3C3C3C3870F0F0F1C3C3C3C78F0F0F0E3C3C3C38F0F0F0F1C3C3C3C70F0F0F0E3C3C3C3870F0F0F1C3C3C3C78F0F0F0E3C3C3C38F0F0F0F1C3C3C3C78F0F0F0E3C3C3C38F0F0F0F1C3C3C3C78F0F0F0E3C3C3C38F0F0F0F1C3C3C3C78F0F0F0E",
        -- CONFIG_07 (In15 -> Out45)
        6 => x"3C3C3C38F1E1E1E1878F0F0F3C3C7878E1E1E3C30F0F0F1E78787878E3C3C3C30F1E1E1E7878F0F0C3C3C7871E1E1E3C70F0F0F1C38787871E1C3C3CF0F0E1E18787870F3C3C3C38E1E1E1E1870F0F0F3C387878E1E1C3C30F0F0E1E78787870E3C3C3C30F1E1E1E7878F0F0C3C3C7871E1E1E3CF0F0F0F1C78787871E3C3C3C",
        -- CONFIG_08 (In15 -> Out60)
        7 => x"3C3C3C38E1E1C3C31E1E1E1EF0F0E1E1870F0F0F787870F0C38787873C3C3C78E1C3C3C31E1E1E3CF0E1E1E10F0F0F1E7878F0F08787878F3C3C7878C3C3C3C31E1E3C3CF1E1E1E10F0F1E1E78F0F0F08787870F3C787878C3C3C3871E3C3C3CE1E1E1C30F0E1E1EF0F0F0E187870F0F78787878C3C387871C3C3C3CE1E1C3C3",
        -- CONFIG_09 (In30 -> Out0)
        8 => x"3336377733363777333637773336377733363777333637773336377733363777333637773336377733363777333637773336377733363777333637773336377733363777333637773336377733363777333637773336377733363777333637773336377733363777333637773336377733363777333637773336377733363777",
        -- CONFIG_10 (In30 -> Out15)
        9 => x"3336377766666666CCCCCCCCCCCCCCCC999999999999999933333333333333336666666666666666CCCCCCCCCCCCCCCC999999999999999933333333333333336666666666666666CCCCCCCCCCCCCCCC999999999999999933333333333333336666666666666666CCCCCCCCCCCCCCCC99999999333333333333333366666666",
        -- CONFIG_11 (In30 -> Out45)
        10 => x"33363777CCCCCCCC9999999966666666CCCCCCCC3333333366666666CCCCCCCC33333333666666669999999933333333666666669999999933333333CCCCCCCC9999999966666666CCCCCCCC9999999966666666CCCCCCCC3333333366666666CCCCCCCC33333333666666669999999933333333CCCCCCCC9999999933333333",
        -- CONFIG_12 (In30 -> Out60) -- Target Steer CONFIG
        11 => x"33363777CCCCCCCC33333333CCCCCCCC99999999666666669999999966666666CCCCCCCC33333333CCCCCCCC33333333666666669999999966666666CCCCCCCC33333333CCCCCCCC333333336666666699999999666666669999999933333333CCCCCCCC33333333CCCCCCCC99999999666666669999999933333333CCCCCCCC",
        -- CONFIG_13 (In45 -> Out0)
        12 => x"6925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B4966925B496",
        -- CONFIG_14 (In45 -> Out15)
        13 => x"6925B4964B6D25B6DB496DA4D25B492D96D24B69B492DA4B25B692DB6DA4B6D2692DA4964B6925B4DA496D2592DB496DB6D25B69B496D24B25B492DA6D24B692496DA4B65B692DB4DA4B692592DA496DB6925B49A4B6D25B2DB496DA6D25B492496D24B65B492DA4D25B692D96DA4B6DB692DA4924B6925B2DA496D2692DB496",
        -- CONFIG_15 (In45 -> Out30)
        14 => x"6925B4965B496DA496DA4B69A4B6925B6925B4965B496DA496DA4B69A4B6925B6925B4965B496DA496DA4B69A4B6925B6925B496DB496DA496DA4B6924B6925B6925B4965B496DA496DA4B69A4B6925B6925B496DB496DA496DA4B69A4B6925B6925B496DB496DA496DA4B69A4B6925B6925B496DB496DA496DA4B69A4B6925B",
        -- CONFIG_16 (In45 -> Out60)
        15 => x"6925B49692DB496D2DA496D2DA496D25A4B6D25B4B6925B4B692DB49692DB49692DA496D6DA4B6D2DA4B692524B6925B5B692DB4B492DA49492DA4B696DA4B6D6D24B696D24B696D25B692D25B692D25B692DA5B492DA4B496DA4B496D24B696D24B696D25B692D25B492D25B492DADB496DA4A496D24B496D25B6B6D25B6969",
        -- CONFIG_17 (In60 -> Out0)
        16 => x"5AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB55AA54AB5",
        -- CONFIG_18 (In60 -> Out15)
        17 => x"5AA54AB556A952ADD5AA54A9B56AD52AA55AB54AA956AD522A55AB544A956AD552A55AB554A956ADD52A55ABB54A952AAD5AA54AAB56A9522AD5AA544AB56A9552AD5AA554AB56A9952AD5AAA54AB56AA952A55AAB54A9566AD52A555AB54A9556AD52A555AB54A9956AD52AA55AB54AA956AD5A2A54AB566A952AD55AA54AB5",
        -- CONFIG_19 (In60 -> Out30)
        18 => x"5AA54AB555AB54A9A55AB54AAA54AB565AA54AB555AB54A9A55AB54AAA54AB565AA54AB555AB54A9A55AB54AAA54AB565AA54AB5D5AB54A9A55AB54A2A54AB565AA54AB555AB54A9A55AB54AAA54AB565AA54AB5D5AB54A9A55AB54AAA54AB565AA54AB5D5AB54A9A55AB54AAA54AB565AA54AB5D5AB54A9A55AB54AAA54AB56",
        -- CONFIG_20 (In60 -> Out45)
        19 => x"5AA54AB5956AD5AAAB54A95652AD5AA5B56A952A2A55AB5456A952A5A54AB56A6AD52A5554A956ADAD5AA54A4A956AD555AB54A9A952AD5A4AB56A95D52A55ABAB56A9525AA54AB5956AD52AAB54A95652AD5AA5B54A952A2A55AB5456A952ADA54AB56A6AD52A5554AB56ADAD5AA54A4A956AD5D5AB54A9A952AD5A5AB54A95"
    );

    -- State Machine definitions
    type state_type is (ST_IDLE, ST_SHIFT_LOW, ST_SHIFT_HIGH, ST_LATCH_PULSE);
    signal current_state, next_state : state_type := ST_IDLE;
    
    -- Clock divider signals (100 MHz to 25 MHz)
    signal clk_div_counter  : unsigned(1 downto 0) := "00";
    signal clk_25mhz        : std_logic := '0';
    signal clk_25mhz_prev   : std_logic := '0';
    signal shift_clk_enable : std_logic := '0';
    
    -- Active buffer registers
    signal active_beam_data : std_logic_vector(1023 downto 0) := (others => '0');
    signal bit_counter      : unsigned(9 downto 0) := (others => '0'); -- 0 to 1023
    
    -- Interface internal lines
    signal sdata_reg        : std_logic := '0';
    signal sclk_reg         : std_logic := '0';
    signal latch_reg        : std_logic := '0';
    signal busy_reg         : std_logic := '0';
    signal start_tx_reg     : std_logic := '0'; -- Latch for 100 MHz pulse

begin

    -- 1. Clock Divider Block: 100 MHz -> 25 MHz
    clk_divider : process(clk_in)
    begin
        if rising_edge(clk_in) then
            if rst_n = '0' then
                clk_div_counter <= "00";
                clk_25mhz <= '0';
            else
                clk_div_counter <= clk_div_counter + 1;
                if clk_div_counter = "01" then
                    clk_25mhz <= '1';
                elsif clk_div_counter = "11" then
                    clk_25mhz <= '0';
                end if;
            end if;
        end if;
    end process;

    -- Edge detection on divided clock to synchronize State Machine logic with 25 MHz borders
    process(clk_in)
    begin
        if rising_edge(clk_in) then
            clk_25mhz_prev <= clk_25mhz;
        end if;
    end process;
    
    shift_clk_enable <= clk_25mhz and (not clk_25mhz_prev); -- Pulse high at rising edge of 25 MHz clock

    -- Latch the 100 MHz start_tx pulse so the 25 MHz state machine sees it
    process(clk_in)
    begin
        if rising_edge(clk_in) then
            if rst_n = '0' then
                start_tx_reg <= '0';
            else
                if start_tx = '1' then
                    start_tx_reg <= '1';
                elsif current_state /= ST_IDLE then
                    start_tx_reg <= '0';
                end if;
            end if;
        end if;
    end process;

    -- 2. State Machine Sync Process (Synchronized with 25 MHz rising edges)
    state_sync : process(clk_in)
    begin
        if rising_edge(clk_in) then
            if rst_n = '0' then
                current_state <= ST_IDLE;
                bit_counter   <= (others => '0');
                active_beam_data <= (others => '0');
                sdata_reg     <= '0';
                sclk_reg      <= '0';
                latch_reg     <= '0';
                busy_reg      <= '0';
            else
                if shift_clk_enable = '1' then
                    current_state <= next_state;
                    
                    case current_state is
                        when ST_IDLE =>
                            bit_counter <= (others => '0');
                            sclk_reg    <= '0';
                            latch_reg   <= '0';
                            busy_reg    <= '0';
                            
                            -- Load BRAM configuration data if triggered
                            if start_tx_reg = '1' then
                                -- Check address limits (only 20 configs: 0 to 19)
                                if unsigned(beam_addr) < 20 then
                                    active_beam_data <= codebook_rom(to_integer(unsigned(beam_addr)));
                                else
                                    active_beam_data <= (others => '0'); -- Default fail-safe state
                                end if;
                                busy_reg <= '1';
                            end if;
                            
                        when ST_SHIFT_LOW =>
                            -- Present serial bit to output pin
                            sdata_reg <= active_beam_data(to_integer(bit_counter));
                            sclk_reg  <= '0'; -- Set clock low
                            busy_reg  <= '1';
                            latch_reg <= '0';
                            
                        when ST_SHIFT_HIGH =>
                            sclk_reg <= '1'; -- Drive clock high to clock data into shift register
                            busy_reg <= '1';
                            bit_counter <= bit_counter + 1;
                            
                        when ST_LATCH_PULSE =>
                            sclk_reg  <= '0';
                            sdata_reg <= '0';
                            latch_reg <= '1'; -- Pulse Latch high
                            busy_reg  <= '1';
                            
                        when others =>
                            current_state <= ST_IDLE;
                    end case;
                end if;
            end if;
        end if;
    end process;

    -- 3. Next State Logic combinational process
    state_logic : process(current_state, start_tx_reg, bit_counter)
    begin
        next_state <= current_state;
        
        case current_state is
            when ST_IDLE =>
                if start_tx_reg = '1' then
                    next_state <= ST_SHIFT_LOW;
                else
                    next_state <= ST_IDLE;
                end if;
                
            when ST_SHIFT_LOW =>
                next_state <= ST_SHIFT_HIGH;
                
            when ST_SHIFT_HIGH =>
                if bit_counter = 1023 then -- Finished all 1024 bits (0 to 1023)
                    next_state <= ST_LATCH_PULSE;
                else
                    next_state <= ST_SHIFT_LOW;
                end if;
                
            when ST_LATCH_PULSE =>
                next_state <= ST_IDLE;
                
            when others =>
                next_state <= ST_IDLE;
        end case;
    end process;

    -- 4. Drive Output Ports
    ris_sclk  <= sclk_reg;
    ris_sdata <= sdata_reg;
    ris_latch <= latch_reg;
    busy      <= busy_reg;

end Behavioral;
