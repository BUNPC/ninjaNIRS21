-- Bernhard Zimmermann - bzim@bu.edu
-- Boston University Neurophotonics Center
-- June 2021

-- Interface for MAX11154

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity ADC_RX is
	port(
		ClkxCI : in std_logic;
		ResetxRI : in std_logic;
		SClrxSI : in std_logic;
		
		CnvxSO	: out std_logic;
--		BusyxSI : in std_logic;
		SDOxDI	: in std_logic;
		SCKxSO	: out std_logic;
		
		PDataxDO	: out std_logic_vector(23 downto 0);
		NSmpsAvxSO : out std_logic_vector(10 downto 0);
		PDataRdReqxSI : in std_logic
	);
end ADC_RX;

architecture Behavioral of ADC_RX is
	constant N_PERIODS_PER_CONV : integer := 90;
	constant N_PERIODS_CNV_HIGH : integer := 26;
	constant N_AVG_CONVS : integer := 7; -- # conversions averaged
	constant N_RX_BITS : integer := 18;
	
	signal ClkCntxDP, ClkCntxDN	: integer range 0 to N_PERIODS_PER_CONV-1;
	signal ConvCntxDP, ConvCntxDN	: integer range 0 to N_AVG_CONVS-1;
	signal BitsCntxDP, BitsCntxDN	: integer range 0 to N_RX_BITS;
	
	type fsmstatetype is (sPreConvStart, sConv, sPostConv, sAcqLow, sAcqHigh, sAvg, sReadComplete, sIdle);
	signal StatexDP, StatexDN : fsmstatetype;	
	attribute syn_encoding : string;
	attribute syn_encoding of fsmstatetype : type is "safe";
	
	signal PDataxDP, PDataxDN : std_logic_vector(PDataxDO'range);
	signal AvgPDataxDP, AvgPDataxDN : std_logic_vector(PDataxDO'range);
	signal FIFOWrReqxS : std_logic;
	
	COMPONENT ADC_RX_FIFO
	PORT(
		clock		: IN STD_LOGIC ;
		data		: IN STD_LOGIC_VECTOR (23 DOWNTO 0);
		rdreq		: IN STD_LOGIC ;
		sclr		: IN STD_LOGIC ;
		wrreq		: IN STD_LOGIC ;
		empty		: OUT STD_LOGIC ;
		full		: OUT STD_LOGIC ;
		q		: OUT STD_LOGIC_VECTOR (23 DOWNTO 0);
		usedw		: OUT STD_LOGIC_VECTOR (10 DOWNTO 0)
	);
	END COMPONENT;
	

begin

	
	p_memzing : process (ClkxCI, ResetxRI)
	begin
      if (rising_edge(ClkxCI)) then
         if (ResetxRI = '1') then
				ClkCntxDP <= 0;
				ConvCntxDP <= 0;
				StatexDP <= sPreConvStart;
				BitsCntxDP <= 0;
         else
				ClkCntxDP <= ClkCntxDN;
				ConvCntxDP <= ConvCntxDN;
				StatexDP <= StatexDN;
				BitsCntxDP <= BitsCntxDN;
         end if;   
			PDataxDP <= PDataxDN;
			AvgPDataxDP <= AvgPDataxDN;
      end if;
   end process;
   
	p_memless : process(StatexDP, ClkCntxDP, PDataxDP, BitsCntxDP, ConvCntxDP, SDOxDI, AvgPDataxDP)
	begin
		CnvxSO <= '0';
		SCKxSO <= '0';
		FIFOWrReqxS <= '0';
		ClkCntxDN <= ClkCntxDP+1;
		PDataxDN <= PDataxDP;
		AvgPDataxDN <= AvgPDataxDP;
		BitsCntxDN <= BitsCntxDP;
		ConvCntxDN <= ConvCntxDP;
		StatexDN <= StatexDP;
		case StatexDP is
			when sPreConvStart => 
				ClkCntxDN <= 0;
				BitsCntxDN <= 0;
				PDataxDN <= (others => '0');
				if SClrxSI = '0' then
					StatexDN <= sConv;
				end if;
				
			when sConv =>
				CnvxSO <= '1';
				if ClkCntxDP >= N_PERIODS_CNV_HIGH-1 then
					StatexDN <= sPostConv;
				end if;
				
			when sPostConv =>
				StatexDN <= sAcqLow;

			when sAcqLow =>
				StatexDN <= sAcqHigh;

			when sAcqHigh =>
				SCKxSO <= '1';
				PDataxDN(PDataxDN'left downto 1) <= PDataxDP(PDataxDN'left-1 downto 0);
				PDataxDN(0) <= SDOxDI;
				if BitsCntxDP >= N_RX_BITS-1 then
					BitsCntxDN <= 0;
					StatexDN <= sAvg;
				else
					StatexDN <= sAcqLow;
					BitsCntxDN <= BitsCntxDP +1;
				end if;
				
			when sAvg =>
				AvgPDataxDN <= std_logic_vector(unsigned(AvgPDataxDP) + unsigned(PDataxDP));
				if ConvCntxDP >= N_AVG_CONVS-1 then
					StatexDN <= sReadComplete;
				else
					ConvCntxDN <= ConvCntxDP +1;
					StatexDN <= sIdle;
				end if;

			when sReadComplete =>
				FIFOWrReqxS <= '1';
				AvgPDataxDN <= (others => '0');
				ConvCntxDN <= 0;
				StatexDN <= sIdle;

			when sIdle =>
				if ClkCntxDP >= N_PERIODS_PER_CONV-2 then
					StatexDN <= sPreConvStart;
				end if;
				
			when others =>
				StatexDN <= sPreConvStart;
		end case;
   end process;
	
	
	ADC_RX_FIFO_inst : ADC_RX_FIFO 
	PORT MAP (
		clock	 => ClkxCI,
		data	 => AvgPDataxDP,
		rdreq	 => PDataRdReqxSI,
		sclr	 => SClrxSI,
		wrreq	 => FIFOWrReqxS,
		empty	 => open,
		full	 => open,
		q	 	 => PDataxDO,
		usedw	 => NSmpsAvxSO
	);
end Behavioral;