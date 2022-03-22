-- Bernhard Zimmermann - bzim@bu.edu
-- Boston University Neurophotonics Center
-- June 2021

LIBRARY ieee;
USE ieee.std_logic_1164.all;
use IEEE.NUMERIC_STD.ALL;


ENTITY LED_MOD IS 
	PORT(
		ClkxCI : IN STD_LOGIC;
		ResetxRI : IN STD_LOGIC;
		LEDEnxSI : IN STD_LOGIC;
		SClrxSI	: IN STD_LOGIC;
		FreqSelxDI : IN STD_LOGIC_VECTOR(4 downto 0);
		ModOutxSO : OUT STD_LOGIC
		);
END LED_MOD;

ARCHITECTURE behavioral OF LED_MOD IS
	
	constant CNT_WIDTH : integer := 14;
	constant N_Freq : integer := 16+1;
	type CntBounds_Array_Type is array (0 to N_Freq-1) of unsigned(CNT_WIDTH-1 downto 0);
	constant ModPeriod_Array : CntBounds_Array_Type := (to_unsigned(1000,CNT_WIDTH),
																		to_unsigned(11520,CNT_WIDTH),
																		to_unsigned(10752,CNT_WIDTH),
																		to_unsigned(10080,CNT_WIDTH),
																		to_unsigned(9216,CNT_WIDTH),
																		to_unsigned(8064,CNT_WIDTH),
																		to_unsigned(7680,CNT_WIDTH),
																		to_unsigned(6720,CNT_WIDTH),
																		to_unsigned(6144,CNT_WIDTH),
																		to_unsigned(11520,CNT_WIDTH), -- repeating for now
																		to_unsigned(10752,CNT_WIDTH),
																		to_unsigned(10080,CNT_WIDTH),
																		to_unsigned(9216,CNT_WIDTH),
																		to_unsigned(8064,CNT_WIDTH),
																		to_unsigned(7680,CNT_WIDTH),
																		to_unsigned(6720,CNT_WIDTH),
																		to_unsigned(6144,CNT_WIDTH)
																		);
	
	constant OnPeriod_Array : CntBounds_Array_Type := (to_unsigned(1000,CNT_WIDTH),
																		to_unsigned(11520/2,CNT_WIDTH),
																		to_unsigned(10752/2,CNT_WIDTH),
																		to_unsigned(10080/2,CNT_WIDTH),
																		to_unsigned(9216/2,CNT_WIDTH),
																		to_unsigned(8064/2,CNT_WIDTH),
																		to_unsigned(7680/2,CNT_WIDTH),
																		to_unsigned(6720/2,CNT_WIDTH),
																		to_unsigned(6144/2,CNT_WIDTH),
																		to_unsigned(11520/2,CNT_WIDTH), -- repeating for now
																		to_unsigned(10752/2,CNT_WIDTH),
																		to_unsigned(10080/2,CNT_WIDTH),
																		to_unsigned(9216/2,CNT_WIDTH),
																		to_unsigned(8064/2,CNT_WIDTH),
																		to_unsigned(7680/2,CNT_WIDTH),
																		to_unsigned(6720/2,CNT_WIDTH),
																		to_unsigned(6144/2,CNT_WIDTH)
																		);
	
	
	signal ClkCntxDP, ClkCntxDN : unsigned(CNT_WIDTH-1 downto 0);
	signal ModOutxDP, ModOutxDN : std_logic;


BEGIN


	ClkCntxDN <= (others => '0') when ClkCntxDP >= (ModPeriod_Array(to_integer(unsigned(FreqSelxDI))) -1) or SClrxSI = '1'
						else ClkCntxDP +1;
	
	ModOutxDN <= '0' when ClkCntxDP < (OnPeriod_Array(to_integer(unsigned(FreqSelxDI))) -1) or LEDEnxSI = '0'
					else '1';
	ModOutxSO <= ModOutxDP;
	
		
	p_memzing : process (ClkxCI, ResetxRI)
	begin
      if (rising_edge(ClkxCI)) then
         if (ResetxRI = '1') then
				ClkCntxDP <= (others => '0');
				ModOutxDP <= '0';
         else
				ClkCntxDP <= ClkCntxDN;
				ModOutxDP <= ModOutxDN;
         end if;  
      end if;
   end process;

END behavioral;