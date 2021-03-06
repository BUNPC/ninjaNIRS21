-- Bernhard Zimmermann - bzim@bu.edu
-- Boston University Neurophotonics Center
-- June 2021

LIBRARY ieee;
USE ieee.std_logic_1164.all;
use IEEE.NUMERIC_STD.ALL;

ENTITY ADC_BRD_ENG IS 
	PORT(
		ClkInxCI : in std_logic;
		ResetxRI : in std_logic;
		AcqEnxSI	: in std_logic;
		
		ADC_SDOxDI : IN STD_LOGIC;
		ADC_SCKxSO : OUT STD_LOGIC;
		ADC_CNVxSO : OUT STD_LOGIC;
		
		OutFIFOCntxSO : out std_logic_vector(9 downto 0);
		OutFIFORdReqxSI : in STD_LOGIC ;
		OutFIFOOutDatxDO	: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
		OutFIFOEmptyxSO : out std_logic
		
		);
END ADC_BRD_ENG;

ARCHITECTURE ADC_BRD_ENG_behavior OF ADC_BRD_ENG IS

	signal ClkxC, ResetxR : std_logic;
	
	signal OutFIFOWrEnxS : std_logic;
	signal OutFIFOInDatxD : std_logic_vector(7 downto 0);
	
	signal ADCDataxD : std_logic_vector(23 downto 0);
	signal ADCDataRdyxS : std_logic;
	
	-- constant N_DFTs_TO_ACQ : integer := 2500; -- # number of samples to acquire per request
	signal DFTCntxDP, DFTCntxDN	: integer range 0 to 255; --N_DFTs_TO_ACQ;
	
	type fsmstatetype is (sIdle, sTxNBytes, sTxDFTCnt, sTxPre1, sTxPre2, sTxBytes, sTxFiller, sWait);
	signal StatexDP, StatexDN : fsmstatetype;
	attribute syn_encoding : string;
	attribute syn_encoding of fsmstatetype : type is "safe";
	
	signal ADCDataRdReqxS : std_logic;
	signal ADCSmpsAvxD : std_logic_vector(10 downto 0);
	
	signal DFTOutFIFODatxD : std_logic_vector(35  downto 0);
	signal DFTOutFIFOCntxS : std_logic_vector(7 downto 0);
	signal DFTOutFIFORdReqxS : std_logic;
	signal DFTRegxDP, DFTRegxDN : signed(DFTOutFIFODatxD'range);
	
	signal DFTAcqStatexDP, DFTAcqStatexDN : std_logic;
	
	signal DataSClrxS : std_logic;
	
	constant N_FREQ : integer := 8+1; -- +1 for max / avg values
	constant N_WORDS_PER_DFT  : integer := 2;
	signal WordCntxDN, WordCntxDP : integer range 0 to N_WORDS_PER_DFT*N_FREQ -1;
	constant N_BYTES_IN_DFT_WORD : integer := 5;
	signal ByteCntxDN, ByteCntxDP : integer range 0 to N_BYTES_IN_DFT_WORD-1;
	
	constant N_FILLER_BYTES : integer := 2;

	
	COMPONENT ADC_RX
	port(
		ClkxCI : in std_logic;
		ResetxRI : in std_logic;
		SClrxSI : in std_logic;
		
		CnvxSO	: out std_logic;
		SDOxDI	: in std_logic;
		SCKxSO	: out std_logic;
		
		PDataxDO	: out std_logic_vector(23 downto 0);
		NSmpsAvxSO : out std_logic_vector(10 downto 0);
		PDataRdReqxSI : in std_logic	
	);
	end COMPONENT;
	
	component DFT_ENG
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
	end component;
	
	component ADC_BRD_ENG_OUT_FIFO
	PORT	(
		clock		: IN STD_LOGIC ;
		data		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
		rdreq		: IN STD_LOGIC ;
		sclr		: IN STD_LOGIC ;
		wrreq		: IN STD_LOGIC ;
		empty		: OUT STD_LOGIC ;
		full		: OUT STD_LOGIC ;
		q		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
		usedw		: OUT STD_LOGIC_VECTOR (9 DOWNTO 0)
	);
	END component;
	
BEGIN

	ClkxC <= ClkInxCI;
	ResetxR <= ResetxRI;
	DFTAcqStatexDN <= AcqEnxSI;
				
	p_memzing : process (ClkxC, ResetxR)
	begin
      if (rising_edge(ClkxC)) then
         if (ResetxR = '1') then
				DFTCntxDP <= 0;
				StatexDP <= sIdle;
				DFTAcqStatexDP <= '0';
         else
				DFTCntxDP <= DFTCntxDN;
				StatexDP <= StatexDN;
				DFTAcqStatexDP <= DFTAcqStatexDN;
         end if;   
		 DFTRegxDP <= DFTRegxDN;
		 WordCntxDP <= WordCntxDN;
		 ByteCntxDP <= ByteCntxDN;
      end if;
   end process;
	   
	p_memless_out_decode : process(StatexDP, ADCDataRdyxS, ADCDataxD, DFTCntxDP, DFTOutFIFODatxD, DFTRegxDP, WordCntxDP, ByteCntxDP)
	begin
		OutFIFOWrEnxS <= '0';
		DFTCntxDN <= DFTCntxDP;
		DFTRegxDN <= signed(DFTOutFIFODatxD);
		OutFIFOInDatxD <= std_logic_vector(DFTRegxDP(7 downto 0));
		--OutFIFOInDatxD <= std_logic_vector(to_unsigned((WordCntxDP mod 256),OutFIFOInDatxD'length));
		DFTOutFIFORdReqxS <= '0';
		WordCntxDN <= WordCntxDP;
		ByteCntxDN <= ByteCntxDP;
		DataSClrxS <= '0';
		case StatexDP is
			when sIdle =>
				DFTCntxDN <= 0;
				ByteCntxDN <= 0;
				WordCntxDN <= 0;
				DataSClrxS <= '1';
			when sWait =>
				WordCntxDN <= 0;
			when sTxNBytes =>
				OutFIFOInDatxD <= std_logic_vector(to_unsigned(1 + N_WORDS_PER_DFT * N_FREQ * N_BYTES_IN_DFT_WORD + N_FILLER_BYTES, OutFIFOInDatxD'length));
				OutFIFOWrEnxS <= '1';				
			when sTxDFTCnt =>
				OutFIFOInDatxD <= std_logic_vector(to_unsigned((DFTCntxDP mod 256),OutFIFOInDatxD'length));
				OutFIFOWrEnxS <= '1';
				DFTCntxDN <= (DFTCntxDP +1) mod 256;
				ByteCntxDN <= 0;
			when sTxPre1 => -- request DFT out word
				DFTOutFIFORdReqxS <= '1';
				ByteCntxDN <= 0;
				
			when sTxPre2 =>
				ByteCntxDN <= 0;
				-- Load DFT out word into shift register
				-- DFTRegxDN <= unsigned(DFTOutFIFODatxD);
			when sTxBytes =>
				DFTRegxDN <= shift_right(DFTRegxDP,8);
				OutFIFOWrEnxS <= '1';
				--ByteCntxDN <= ByteCntxDP +1;
				if ByteCntxDP >= N_BYTES_IN_DFT_WORD-1 then
					WordCntxDN <= WordCntxDP +1;
					ByteCntxDN <= 0;
				else
					ByteCntxDN <= ByteCntxDP +1;
				end if;
				
			when sTxFiller =>
				OutFIFOWrEnxS <= '1';
				OutFIFOInDatxD <= std_logic_vector(to_unsigned(170,8));
				ByteCntxDN <= ByteCntxDP +1;
			
			when others =>
		end case;
   end process;
   
	p_memless_next_state_decode : process (StatexDP, DFTOutFIFOCntxS, ByteCntxDP, WordCntxDP, DFTAcqStatexDP)
	begin
		StatexDN <= StatexDP;
		case StatexDP is
			when sIdle =>
				if DFTAcqStatexDP = '1' then
					StatexDN <= sWait;
				end if;
			when sWait =>
				if DFTAcqStatexDP = '0' then
					StatexDN <= sIdle;
				elsif DFTAcqStatexDP = '1' and to_integer(unsigned(DFTOutFIFOCntxS)) >=  N_WORDS_PER_DFT*N_FREQ then
					StatexDN <= sTxNBytes;
				end if;
			when sTxNBytes =>
				StatexDN <= sTxDFTCnt;
			when sTxDFTCnt =>
				StatexDN <= sTxPre1;
			when sTxPre1 =>
				StatexDN <= sTxPre2;
			when sTxPre2 =>
				StatexDN <= sTxBytes;
			when sTxBytes =>
				if (ByteCntxDP >= N_BYTES_IN_DFT_WORD-1) and (WordCntxDP >= N_WORDS_PER_DFT*N_FREQ  -1) then
					StatexDN <= sTxFiller;
				elsif (ByteCntxDP >= N_BYTES_IN_DFT_WORD-1) and (WordCntxDP < N_WORDS_PER_DFT*N_FREQ  -1) then
					StatexDN <= sTxPre1;
				end if;
			when sTxFiller => 
				if ByteCntxDP >= N_FILLER_BYTES-1 then
					StatexDN <= sWait;
				end if;
				
			when others =>
				StatexDN <= sIdle;
		end case;	
   end process;
	
	ADC_BRD_ENG_OUT_FIFO_inst : ADC_BRD_ENG_OUT_FIFO
	port map	(
		clock	=> ClkxC,
		data	=> OutFIFOInDatxD,
		rdreq => OutFIFORdReqxSI,
		sclr	=> DataSClrxS,
		wrreq	=> OutFIFOWrEnxS,
		empty	=> OutFIFOEmptyxSO,
		full	=> open,
		q		=> OutFIFOOutDatxDO,
		usedw	=> OutFIFOCntxSO
	);
	
	
	ADC_RX_inst : ADC_RX
		port map(
			ClkxCI => ClkxC,
			ResetxRI => ResetxR,
			SClrxSI => DataSClrxS,
			
			CnvxSO => ADC_CNVxSO,
			SDOxDI => ADC_SDOxDI,
			SCKxSO => ADC_SCKxSO,
			
			PDataxDO => ADCDataxD,
			NSmpsAvxSO => ADCSmpsAvxD,
			PDataRdReqxSI => ADCDataRdReqxS
		);
		
	DFT_ENG_inst : DFT_ENG 
		port map(
			ClkxCI 	=> ClkxC,
			ResetxRI => DataSClrxS,
			
			RawDatxDI => ADCDataxD,	
			RawDatCntxDI => ADCSmpsAvxD,
			RawDatRdReqxSO => ADCDataRdReqxS,
			
			OutFIFOCntxSO => DFTOutFIFOCntxS,
			OutFIFORdReqxSI => DFTOutFIFORdReqxS,
			OutFIFODatxDO => DFTOutFIFODatxD	
			
		);

END ADC_BRD_ENG_behavior;