-- Create Date: 15:25:23 01/11/2019
-- Interface for Power Distribution Board

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity SREG_IN_OUT is
	port(
		ClkxCI : in std_logic;
		ResetxRI : in std_logic;
		
		PDat0xDI : in std_logic_vector(7 downto 0);
		PDat1xDI : in std_logic_vector(7 downto 0);
		
		PDat0xDO : out std_logic_vector(7 downto 0);
		PDat1xDO : out std_logic_vector(7 downto 0);
		
		SRegOutDatxDO : out std_logic;
		SRegShClkxSO : out std_logic;
		SRegOutClkxSO : out std_logic;
		SRegInLoadxSOB : out std_logic;
		SRegInDatxDI : in std_logic;
		SRegOExSOB : out std_logic
	);
end SREG_IN_OUT;

architecture Behavioral of SREG_IN_OUT is
	constant N_CLKS_PER_UPDATE : integer := 30000;
	constant N_CLK_DIV : integer := 32;
	constant N_REGS : integer := 2;
	
	type PDat_Array_Type is array (0 to N_REGS-1) of std_logic_vector(7 downto 0);
	signal PDatInxD : PDat_Array_Type; 
	signal PDatOutxDP, PDatOutxDN : PDat_Array_Type; 
	
	
	signal ClkCntxDP, ClkCntxDN	: integer range 0 to N_CLKS_PER_UPDATE-1;
	signal RegCntxDP, RegCntxDN	: integer range 0 to N_REGS-1;
	signal BitCntxDP, BitCntxDN	: integer range 0 to 7;
	signal SRegOutxDP, SRegOutxDN : std_logic_vector(7 downto 0);
	signal SRegInxDP, SRegInxDN : std_logic_vector(7 downto 0);
	signal OEStatexSP, OEStatexSN : std_logic := '0';
		
	type fsmstatetype is (sIdle, sLoad, sClkLow, sClkHigh, sShiftOut, sShiftIn, sLatchInOut);
	signal StatexDP, StatexDN : fsmstatetype;	
	attribute syn_encoding : string;
	attribute syn_encoding of fsmstatetype : type is "safe";
	
begin

	-- this can be done better with a package
	PDatInxD(0) <= PDat0xDI;
	PDatInxD(1) <= PDat1xDI;
	PDat0xDO <= PDatOutxDP(0);
	PDat1xDO <= PDatOutxDP(1);
		
	SRegOExSOB <= not OEStatexSP;
	SRegOutDatxDO <= SRegOutxDP(7);
	
	p_memzing : process (ClkxCI, ResetxRI)
	begin
      if (rising_edge(ClkxCI)) then
         if (ResetxRI = '1') then
				ClkCntxDP <= 0;
				RegCntxDP <= 0;
				StatexDP <= sIdle;
				BitCntxDP <= 0;
				SRegOutxDP <= (others => '0');
				OEStatexSP <= '0';
				PDatOutxDP <= (others => (others => '0'));
				SRegInxDP <= (others => '0');
         else
				ClkCntxDP <= ClkCntxDN;
				RegCntxDP <= RegCntxDN;
				StatexDP <= StatexDN;
				BitCntxDP <= BitCntxDN;
				SRegOutxDP <= SRegOutxDN;
				OEStatexSP <= OEStatexSN;
				PDatOutxDP <= PDatOutxDN;
				SRegInxDP <= SRegInxDN;
         end if;   
      end if;
   end process;
   
   
	p_memless_next_state_decode : process (StatexDP, BitCntxDP, SRegOutxDP, RegCntxDP, ClkCntxDP, OEStatexSP, PDatInxD, SRegInxDP, PDatOutxDP, SRegInDatxDI)
	begin
		StatexDN <= StatexDP;
		ClkCntxDN <= 0;
		BitCntxDN <= BitCntxDP;
		SRegOutxDN <= SRegOutxDP;
		SRegInxDN <= SRegInxDP;
		RegCntxDN <= RegCntxDP;
		SRegShClkxSO <= '0';
		SRegOutClkxSO <= '0';
		OEStatexSN <= OEStatexSP;
		SRegInLoadxSOB <= '1';
		PDatOutxDN <= PDatOutxDP;
		case StatexDP is
			when sIdle =>				
				if ClkCntxDP >= N_CLKS_PER_UPDATE-1 then
					StatexDN <= sLoad;
					ClkCntxDN <= 0;
				else 
					ClkCntxDN <= ClkCntxDP +1;
				end if;
				RegCntxDN <= N_REGS-1;

			when sLoad =>
				StatexDN <= sShiftIn;
				SRegOutxDN <= PDatInxD(RegCntxDP);
				BitCntxDN <= 0;
				
			when sShiftIn => 
				StatexDN <= sClkLow;
				SRegInxDN(0) <= SRegInDatxDI;
				SRegInxDN(7 downto 1) <= SRegInxDP(6 downto 0);
			
			when sClkLow =>
				if ClkCntxDP >= N_CLK_DIV-2 then
					StatexDN <= sClkHigh;
					ClkCntxDN <= 0;
				else
					ClkCntxDN <= ClkCntxDP +1;
				end if;
			
			when sClkHigh =>
				SRegShClkxSO <= '1';
				ClkCntxDN <= ClkCntxDP +1;
				if ClkCntxDP >= N_CLK_DIV-2 then
					StatexDN <= sShiftOut;
				end if;				
			
			when sShiftOut =>
				SRegOutxDN(7 downto 1) <= SRegOutxDP(6 downto 0);
				SRegOutxDN(0) <= '0';
				ClkCntxDN <= 0;
				if BitCntxDP >= 7 then
					PDatOutxDN(N_REGS - RegCntxDP -1) <= SRegInxDP;
					if RegCntxDP = 0 then
						StatexDN <= sLatchInOut;
					else
						StatexDN <= sLoad;
						RegCntxDN <= RegCntxDP - 1;
					end if;
				else
					StatexDN <= sShiftIn;
					BitCntxDN <= BitCntxDP +1;
				end if;
				
			when sLatchInOut =>
				SRegInLoadxSOB <= '0';
				SRegOutClkxSO <= '1';
				if ClkCntxDP >= N_CLK_DIV-2 then
					OEStatexSN <= '1';
					StatexDN <= sIdle;
					ClkCntxDN <= 0;
				else
					ClkCntxDN <= ClkCntxDP +1;
				end if;
				
			when others =>
				StatexDN <= sIdle;
		end case;	
   end process;
	
end Behavioral;