-- Bernhard Zimmermann - bzim@bu.edu
-- Boston University Neurophotonics Center
-- June 2021


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity DFT_ENG is
	port (
		ClkxCI 	 : in std_logic;
		ResetxRI : in std_logic;
		
		RawDatxDI : in std_logic_vector(23 downto 0);
		RawDatCntxDI : in std_logic_vector(10 downto 0);
		RawDatRdReqxSO : out std_logic;
		
		--OutFIFOEmptyxSO : out std_logic;
		OutFIFOCntxSO : out std_logic_vector(7 downto 0);
		OutFIFORdReqxSI : in STD_LOGIC ;
		OutFIFODatxDO	: OUT STD_LOGIC_VECTOR (35 DOWNTO 0)
		
	);
end DFT_ENG;

architecture Behavioral of DFT_ENG is
	constant DFT_N : integer := 1024;
	constant TRUNCATE_N_ADC_BITS : integer := 0;
	--constant KMult : std_logic_vector(31 downto 0) := std_logic_vector(to_signed(1984016189,32)); -- 2*cos(2*pi*16/256)*2^30 = 1984016189
	-- Matlab: sprintf('%0.0f ',round(2*cos(2*pi*([18 20 21 24 28 30 32 35])/128)*2^30))
	-- Matlab: sprintf('%0.0f ',round(2*cos(2*pi*([56 60 64 70 80 84 96 105])/512)*2^30))
	constant N_FREQ : integer := 8;
	type KMult_Array_Type is array (0 to N_FREQ-1) of std_logic_vector(31 downto 0);
	constant KMult_Array : KMult_Array_Type := (std_logic_vector(to_signed(2021950484,32)), 
														std_logic_vector(to_signed(2003586779,32)),
														std_logic_vector(to_signed(1984016189,32)),
														std_logic_vector(to_signed(1952423377,32)),
														std_logic_vector(to_signed(1893911494,32)),
														std_logic_vector(to_signed(1868497586,32)),
														std_logic_vector(to_signed(1785567396,32)),
														std_logic_vector(to_signed(1716993211,32))			
														);
														-- 2021950484 2003586779 1984016189 1952423377 1893911494 1868497586 1785567396 1716993211

	signal KMultxD : std_logic_vector(31 downto 0);
	signal FreqCntxDP, FreqCntxDN : integer range 0 to N_FREQ-1;

	type fsmstatetype is (sIdle, sPreLoad, sLoad, sPostLoad, sPreCompute1, sPreCompute2, sCompute, sPostCompute1, sPostCompute2, sPostCompute3, sPostCompute4,
		sAvgMaxPreCompute1, sAvgMaxPreCompute2, sAvgMaxCompute, sAvgMaxPostCompute1, sAvgMaxPostCompute2, sAvgMaxPostCompute3, sAvgMaxPostCompute4);
	signal StatexDP, StatexDN : fsmstatetype;
	attribute syn_encoding : string;
	attribute syn_encoding of fsmstatetype : type is "safe";

	signal SmpCntxDP, SmpCntxDN : integer range 0 to DFT_N-1;
	
	signal YNxDP, YNxDN : signed(35 downto 0);
	signal YNPrexDP, YNPrexDN : signed(35 downto 0);
	
	signal OutFIFODatInxD : std_logic_vector(YNxDP'range);

	signal RAMOutxD : std_logic_vector(23 downto 0);
	signal RAMAddrxD	: STD_LOGIC_VECTOR (9 DOWNTO 0);
	signal RAMWrENxS : std_logic;
	
	signal OutFIFOWrReqxS : std_logic;
	
	signal MultOutxD : std_logic_vector(67 DOWNTO 0);
	signal MultAxD : std_logic_vector(YNxDP'range);
	
		
	COMPONENT DFT_ENG_RAM
	PORT
	(
		address		: IN STD_LOGIC_VECTOR (9 DOWNTO 0);
		clock		: IN STD_LOGIC  := '1';
		data		: IN STD_LOGIC_VECTOR (23 DOWNTO 0);
		wren		: IN STD_LOGIC ;
		q		: OUT STD_LOGIC_VECTOR (23 DOWNTO 0)
	);
	END COMPONENT;
	
	COMPONENT DFT_ENG_FIFO
	PORT
	(
		clock		: IN STD_LOGIC ;
		data		: IN STD_LOGIC_VECTOR (35 DOWNTO 0);
		rdreq		: IN STD_LOGIC ;
		sclr		: IN STD_LOGIC ;
		wrreq		: IN STD_LOGIC ;
		usedw		: OUT STD_LOGIC_VECTOR(7 DOWNTO 0) ;
		empty		: OUT STD_LOGIC ;
		full		: OUT STD_LOGIC ;
		q		: OUT STD_LOGIC_VECTOR (35 DOWNTO 0)
	);
	END COMPONENT;
	
	COMPONENT DFT_ENG_MULT
	PORT
	(
		--clock		: IN STD_LOGIC ;
		dataa		: IN STD_LOGIC_VECTOR (35 DOWNTO 0);
		datab		: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		result	: OUT STD_LOGIC_VECTOR (67 DOWNTO 0)
	);
	END COMPONENT;

	
begin

	p_memzing : process (ClkxCI, ResetxRI)
	begin
      if (rising_edge(ClkxCI)) then
         if (ResetxRI = '1') then
				StatexDP <= sIdle;
				SmpCntxDP <= 0;
				FreqCntxDP <= 0;
				YNxDP <= (others => '0');
				YNPrexDP <= (others => '0');
         else
				StatexDP <= StatexDN;
				SmpCntxDP <= SmpCntxDN;
				FreqCntxDP <= FreqCntxDN;
				YNxDP <= YNxDN;
				YNPrexDP <= YNPrexDN;
         end if;  
			
      end if;
   end process;
   
	RAMAddrxD <= std_logic_vector(to_unsigned(SmpCntxDP,10));
		
	p_memless_out_decode : process (StatexDP, SmpCntxDP, RAMOutxD, MultOutxD, YNxDP, YNPrexDP, FreqCntxDP)
	begin
		SmpCntxDN <= 0;
		FreqCntxDN <= FreqCntxDP;
		YNxDN <= (others => '0');
		YNPrexDN <= YNxDP;
		OutFIFOWrReqxS <= '0';
		OutFIFODatInxD <= std_logic_vector(YNxDP);
		RAMWrENxS <= '0';
		RawDatRdReqxSO <= '0';
		case StatexDP is
			when sIdle =>
				FreqCntxDN <= 0;
				
			when sPreLoad =>
				RawDatRdReqxSO <= '1';
				FreqCntxDN <= 0;
								
			when sLoad =>
				SmpCntxDN <= SmpCntxDP +1;
				FreqCntxDN <= 0;
				RAMWrENxS <= '1';
				RawDatRdReqxSO <= '1';
				
			when sPostLoad =>
				-- SmpCntxDN <= 0;
				FreqCntxDN <= 0;
				RAMWrENxS <= '1';
				
			when sPreCompute1 => -- SmpCntxDP = 0
				SmpCntxDN <= SmpCntxDP +1;
				
			when sPreCompute2 => -- SmpCntxDP = 1
				SmpCntxDN <= SmpCntxDP +1;
				
			when sCompute =>
				if SmpCntxDP < DFT_N-1 then
					SmpCntxDN <= SmpCntxDP +1;
				end if;
				YNxDN <= resize(shift_right(signed('0' & RAMOutxD),TRUNCATE_N_ADC_BITS),36) + resize(shift_right(signed(MultOutxD),30),36) - YNPrexDP;
				
			when sPostCompute1 =>
				YNxDN <= resize(shift_right(signed('0' & RAMOutxD),TRUNCATE_N_ADC_BITS),36) + resize(shift_right(signed(MultOutxD),30),36) - YNPrexDP;
	
			when sPostCompute2 =>
				YNxDN <= resize(shift_right(signed('0' & RAMOutxD),TRUNCATE_N_ADC_BITS),36) + resize(shift_right(signed(MultOutxD),30),36) - YNPrexDP;
				
			when sPostCompute3 =>
				OutFIFOWrReqxS <= '1';
				YNxDN <= resize(shift_right(signed(MultOutxD),30),36) - YNPrexDP;
				
			when sPostCompute4 =>
				OutFIFOWrReqxS <= '1';
				if FreqCntxDP < (N_FREQ-1) then
					FreqCntxDN <= FreqCntxDP +1;
				else
					FreqCntxDN <= 0;
				end if;
				
			when sAvgMaxPreCompute1 => -- SmpCntxDP = 0
				SmpCntxDN <= SmpCntxDP +1;
				
			when sAvgMaxPreCompute2 => -- SmpCntxDP = 1
				SmpCntxDN <= SmpCntxDP +1;
			
			when sAvgMaxCompute =>
				if SmpCntxDP < DFT_N-1 then
					SmpCntxDN <= SmpCntxDP +1;
				end if;
				YNxDN <= resize(signed('0' & RAMOutxD),36) + YNxDP;
				if resize(signed('0' & RAMOutxD),36) > YNPrexDP then
					YNPrexDN <= resize(signed('0' & RAMOutxD),36);
				else
					YNPrexDN <= YNPrexDP;
				end if;
			
			when sAvgMaxPostCompute1 => 
				YNxDN <= resize(signed('0' & RAMOutxD),36) + YNxDP;
				if resize(signed('0' & RAMOutxD),36) > YNPrexDP then
					YNPrexDN <= resize(signed('0' & RAMOutxD),36);
				else
					YNPrexDN <= YNPrexDP;
				end if;
						
			when sAvgMaxPostCompute2 =>
				YNxDN <= resize(signed('0' & RAMOutxD),36) + YNxDP;
				if resize(signed('0' & RAMOutxD),36) > YNPrexDP then
					YNPrexDN <= resize(signed('0' & RAMOutxD),36);
				else
					YNPrexDN <= YNPrexDP;
				end if;
						
			when sAvgMaxPostCompute3 => -- transmit max value
				OutFIFODatInxD <= std_logic_vector(YNPrexDP);
				OutFIFOWrReqxS <= '1';
				-- YNPrexDN <= YNxDP;
				
			when sAvgMaxPostCompute4 => -- transmit avg value
				OutFIFODatInxD <= std_logic_vector(YNPrexDP);
				OutFIFOWrReqxS <= '1';
			
			
			when others =>
		end case;
   end process;
   
	p_memless_next_state_decode : process (StatexDP, RawDatCntxDI, SmpCntxDP, FreqCntxDP)
	begin
		StatexDN <= StatexDP;
		case StatexDP is
			when sIdle =>
				if to_integer(unsigned(RawDatCntxDI)) > DFT_N then
					StatexDN <= sPreLoad;
				end if;
			when sPreLoad =>
				StatexDN <= sLoad;
			when sLoad =>
				if SmpCntxDP >= DFT_N-2 then
					StatexDN <= sPostLoad;
				end if;
			when sPostLoad =>
				StatexDN <= sPreCompute1;
			when sPreCompute1 =>
				StatexDN <= sPreCompute2;
			when sPreCompute2 =>
				StatexDN <= sCompute;
			when sCompute =>
				if SmpCntxDP >= DFT_N-1 then
					StatexDN <= sPostCompute1;
				end if;
			when sPostCompute1 =>
				StatexDN <= sPostCompute2;
			when sPostCompute2 =>
				StatexDN <= sPostCompute3;
			when sPostCompute3 =>
				StatexDN <= sPostCompute4;
			when sPostCompute4 =>
				if FreqCntxDP < (N_FREQ-1) then
					StatexDN <= sPreCompute1;
				else
					StatexDN <= sAvgMaxPreCompute1;
				end if;
				
			when sAvgMaxPreCompute1 => 
				StatexDN <= sAvgMaxPreCompute2;
			when sAvgMaxPreCompute2 =>
				StatexDN <= sAvgMaxCompute;
			when sAvgMaxCompute =>
				if SmpCntxDP >= DFT_N-1 then
					StatexDN <= sAvgMaxPostCompute1;
				end if;
			when sAvgMaxPostCompute1 => 
				StatexDN <= sAvgMaxPostCompute2;
			when sAvgMaxPostCompute2 =>
				StatexDN <= sAvgMaxPostCompute3;
			when sAvgMaxPostCompute3 =>
				StatexDN <= sAvgMaxPostCompute4;
			when sAvgMaxPostCompute4 =>
				StatexDN <= sIdle;
				
			when others =>
				StatexDN <= sIdle;
		end case;	
   end process;

	DFT_ENG_RAM_inst : DFT_ENG_RAM
	PORT MAP
	(
		address =>	RAMAddrxD,	--: IN STD_LOGIC_VECTOR (8 DOWNTO 0);
		clock	=> ClkxCI,			--: IN STD_LOGIC  := '1';
		data	=> RawDatxDI,		--: IN STD_LOGIC_VECTOR (23 DOWNTO 0);
		wren	=> RAMWrENxS,		--: IN STD_LOGIC ;
		q		=> RAMOutxD		--: OUT STD_LOGIC_VECTOR (23 DOWNTO 0)
	);
	
	MultAxD <= std_logic_vector(YNxDP);
	KMultxD <= KMult_Array(FreqCntxDP);
	
	DFT_ENG_MULT_inst : DFT_ENG_MULT
	PORT MAP
	(
		--clock	=> ClkxCI,	--: IN STD_LOGIC ;
		dataa	=> MultAxD,	--: IN STD_LOGIC_VECTOR (35 DOWNTO 0);
		datab	=>	KMultxD, --: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		result => MultOutxD		--: OUT STD_LOGIC_VECTOR (67 DOWNTO 0)
	);
	
	DFT_ENG_FIFO_inst : DFT_ENG_FIFO
	PORT MAP
	(
		clock	=> ClkxCI,		--: IN STD_LOGIC ;
		data	=>	OutFIFODatInxD,	--: IN STD_LOGIC_VECTOR (31 DOWNTO 0);
		rdreq	=>	OutFIFORdReqxSI,				--: IN STD_LOGIC ;
		sclr =>	ResetxRI,				--: IN STD_LOGIC ;
		wrreq	=>	OutFIFOWrReqxS,
		usedw	=>	OutFIFOCntxSO,		--: IN STD_LOGIC ;
		empty	=>	open,			--: OUT STD_LOGIC ;
		full =>	open,				--: OUT STD_LOGIC ;
		q =>	OutFIFODatxDO	--: OUT STD_LOGIC_VECTOR (31 DOWNTO 0)
	);

end Behavioral;