-- Bernhard Zimmermann - bzim@bu.edu
-- Boston University Neurophotonics Center
-- June 2021

LIBRARY ieee;
USE ieee.std_logic_1164.all;
use IEEE.NUMERIC_STD.ALL;

ENTITY ControlCard00_00 IS 
	PORT(
		DebugLEDxSO : OUT STD_LOGIc_VECTOR(5 downto 0);
		
		HostFtdiUARTTxxDO : OUT STD_LOGIC;
		HostFtdiUARTRxxDI : IN STD_LOGIC;
		
		HostFtdiUARTRTSxSIB: IN STD_LOGIC;
		HostFtdiUARTCTSxSOB : OUT STD_LOGIC;
		--HostFtdiUARTDTRxSI: IN STD_LOGIC;
		--HostFtdiUARTDSRxSO : OUT STD_LOGIC;
		--HostFtdiUARTDCDxSO : OUT STD_LOGIC;
--		PortPwrEnxSO : out std_logic_vector(7 downto 0);
--		PortLedRxSO : out std_logic_vector(7 downto 0);
--		PortLedGxSO : out std_logic_vector(7 downto 0);
		
--		EXP_LEDxDO : out std_logic_vector(11 downto 0);
		EXP_CNVxDO : out std_logic_vector(11 downto 0);
		EXP_SCKxDO : out std_logic_vector(1 downto 0);
--		EXP_BUSYxDI : in std_logic_vector(11 downto 0);
		EXP_SDOxDI : in std_logic_vector(11 downto 0);
		
		AUX_CSnxSO : out std_logic_vector(1 downto 0);
		AUX_SCLKxSO : out std_logic_vector(1 downto 0);
		AUX_SDOxDI : in std_logic_vector(1 downto 0);
		
		ArduUARTRxxDI : in std_logic;
		--ArduUARTTxxDO : out std_logic;
		ArduTrgOutxSO : out std_logic;
		ArduEnxSO : out std_logic;
		
		AuxTrgOutxSO : out std_logic;
		
		LED730xDO : out std_logic_vector(11 downto 0);
		LED850xDO : out std_logic_vector(11 downto 0);
		LEDhighxDO : out std_logic_vector(1 downto 0);
		
		DetPwrxSO : out std_logic_vector(2 downto 0);
		SrcPwrxSO : out std_logic_vector(2 downto 0);
				
--		LaserModxDO : out std_logic;
				
		Clk32InxCI : IN STD_LOGIC;
		Clk32EnxSO : OUT STD_LOGIC
--		Clk40InxCI : IN STD_LOGIC
		);
END ControlCard00_00;

ARCHITECTURE ControlCard00_00_behavior OF ControlCard00_00 IS

	signal ResetxR, ClkxC, UARTClkxC : std_logic;
	
	signal AcqEnxS : std_logic;
		
	-- FROM OPTODE to HOST signals
	
	constant N_ADC : integer := 12;
	constant N_SRC_OPTODES : integer := 8;
	constant N_BYTES_PER_SAMPLE : integer := 95;
	
	constant N_TRG_CLK_PERIODS : integer := 90*7*1024;
	constant N_TRG_HIGH : integer := N_TRG_CLK_PERIODS/2;
	constant N_SMP_PER_TRG : integer := 250;
	constant N_TRG_WRAP : integer := 100;
	signal TrgClkCntxDN, TrgClkCntxDP : integer range 0 to N_TRG_CLK_PERIODS-1;
	signal TrgSmpCntxDN, TrgSmpCntxDP : integer range 0 to N_SMP_PER_TRG-1;
	signal TrgCntxDN, TrgCntxDP : integer range 0 to N_TRG_WRAP-1;
	
	signal FromArduFIFOPDatxD : std_logic_vector(7 downto 0);
	signal FromArduFIFOCntxS : std_logic_vector(9 downto 0);
	signal FromArduFIFORdAcqxS : std_logic;
	signal FromArduFIFOEmptyxS : std_logic;
	
	signal ADC_BRD_FIFOEmptyxS : std_logic_vector(N_ADC-1 downto 0);
	signal ADC_BRD_FIFORdAcqxS : std_logic_vector(N_ADC-1 downto 0);
	
	type ADC_BRD_FIFOCnt_Array_Type is array (0 to N_ADC-1) of std_logic_vector(9 downto 0);
	signal ADC_BRD_FIFOCntxS : ADC_BRD_FIFOCnt_Array_Type;
	
	type ADC_BRD_FIFOPDat_Array_Type is array (0 to N_ADC-1) of std_logic_vector(7 downto 0);
	signal ADC_BRD_FIFOPDatxD : ADC_BRD_FIFOPDat_Array_Type;
	
	signal AUX_FIFOEmptyxS : std_logic;
	signal AUX_FIFORdAcqxS : std_logic;
	signal AUX_FIFOCntxS : std_logic_vector(9 downto 0);
	signal AUX_FIFOPDatxD : std_logic_vector(7 downto 0);

	type ADC_BRD_fsmstatetype is (sCheck, sTxADC_N, sTxData, sNextADC, sTx200, sTxAUX, sTx201, sTxARDU, sTx254, sTxSReg, sTxFiller);
	signal ADC_BRD_StatexDP, ADC_BRD_StatexDN : ADC_BRD_fsmstatetype;	
	attribute syn_encoding : string;
	attribute syn_encoding of ADC_BRD_fsmstatetype : type is "safe";
	
	signal ADC_BRD_IIxDP, ADC_BRD_IIxDN : integer range 0 to N_ADC-1;
	signal ADC_BRD_ByteCntxDP, ADC_BRD_ByteCntxDN : integer range 0 to 255;
		
	signal ToHostUARTPDatxD : std_logic_vector(7 downto 0);
	signal ToHostUARTPDatRdyxS : std_logic;
	-- signal ToHostUARTFIFOCntxS : std_logic_vector(15 downto 0);
	
	constant N_STATUS_REG : integer := 9;
	constant N_WRITABLE_SREG : integer := 4;
	type STATUS_REG_Array_Type is array (0 to N_STATUS_REG-1) of std_logic_vector(7 downto 0);
	signal SRegxDP, SRegxDN : STATUS_REG_Array_Type := ((others => '0'),(others => '0'),(others => '0'),(others => '0'),(others => '0'),(others => '0'),(others => '0'),(others => '0'),(others => '0'));
	
	signal TxSRegxDP, TxSRegxDN : std_logic;
	signal TxSRegSetxS, TxSRegClrxS : std_logic;
	
	signal TxSRegCntxDP, TxSRegCntxDN : integer range 0 to N_BYTES_PER_SAMPLE -1;
	
	
	-- FROM HOST DEVICE to OPTODE signals
	
	type fromhost_fsmstatetype is (sWait, sRxData);
	signal FromHostStatexDP, FromHostStatexDN : fromhost_fsmstatetype;	
	--attribute syn_encoding : string;
	attribute syn_encoding of fromhost_fsmstatetype : type is "safe";
	
	
	signal FromHostFIFOPDatxD : std_logic_vector(7 downto 0);
	signal FromHostFIFOEmptyxS : std_logic;
	signal FromHostFIFORdAcqxS : std_logic;
	
	signal FromHostByteCntxDP, FromHostByteCntxDN : integer range 0 to N_STATUS_REG-1;
	
	
	signal FromHostUARTPDatRdyxS : std_logic;
	signal FromHostFIFOCntxS : std_logic_vector(9 downto 0);
	
	signal UARTPDatRdyxS, UartTxPDatRdyxS, BuffFullxS : std_logic;
	signal UARTPDatxD, UartTxPDatxD : std_logic_vector(7 downto 0);
	signal UARTRegxDP, UARTRegxDN : std_logic_vector(7 downto 0);
	
	signal UARTTxxS : std_logic;
	
	signal PLLLockedxS : std_logic;
	
	signal EXP_SCKxD : std_logic_vector(N_ADC-1 downto 0);

			
	component MainPLL IS
		PORT
		(
			areset		: IN STD_LOGIC  := '0';
			inclk0		: IN STD_LOGIC  := '0';
			c0		: OUT STD_LOGIC ;
			c1		: OUT STD_LOGIC ;
			locked		: OUT STD_LOGIC 
		);
	END component;

--	component UART_TX
--		GENERIC(
--			TX_CLK_DIV : integer := 4
--		); 
--		port (
--			ClkxCI 	 : in std_logic;
--			ResetxRI : in std_logic;
--			CTSxSIB	: in std_logic;
--			TxOutxDO : out std_logic;
--			FIFOFullxSO  : out std_logic;
--			FIFOWrEnxSI : in std_logic;
--			FIFOPDatxDI : in std_logic_vector(7 downto 0);
--			FIFOCntxSO : OUT std_logic_vector(9 downto 0)	
--		);
--	end component;
	
	component UART_TX_HOST
		GENERIC(
			TX_CLK_DIV : integer := 4
		); 
		port (
			ClkxCI 	 : in std_logic;
			FIFOClkxCI : in std_logic;
			ResetxRI : in std_logic;
			CTSxSIB	: in std_logic;
			TxOutxDO : out std_logic;
			FIFOFullxSO  : out std_logic;
			FIFOWrEnxSI : in std_logic;
			FIFOPDatxDI : in std_logic_vector(7 downto 0);
			FIFOCntxSO : OUT std_logic_vector(15 downto 0)	
		);
	end component;
	
	component UART_RX 
		generic(
			RX_CLK_DIV : integer := 4
			); 
		port(
			ClkxCI : IN STD_LOGIC;
			FIFOClkxCI : IN STD_LOGIC;
			ResetxRI : IN STD_LOGIC;
			RxInxDI	: IN STD_LOGIC;
			FIFOPDatxDO : OUT std_logic_vector(7 downto 0);
			FIFOEmptyxSO : OUT std_logic;
			FIFOFullxSO : OUT std_logic;
			FIFOCntxSO : OUT std_logic_vector(9 downto 0);
			FIFORdAcqxSI : IN std_logic	
			);
	end component;
	
	component LED_MOD
	PORT(
		ClkxCI : IN STD_LOGIC;
		ResetxRI : IN STD_LOGIC;
		SClrxSI	: IN STD_LOGIC;
		LEDEnxSI : IN STD_LOGIC;
		FreqSelxDI : IN STD_LOGIC_VECTOR(4 downto 0);
		ModOutxSO : OUT STD_LOGIC
		);
	END component;
	
	component ADC_BRD_ENG
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
		OutFIFOEmptyxSO : OUT STD_LOGIC
		
		);
	END component;
	
	component AUX_ADC_RX
	port(
		ClkxCI : in std_logic;
		ResetxRI : in std_logic;
		SClrxSI : in std_logic;
		AcqEnxSI	: in std_logic;
		
		CSnxSO	: out std_logic_vector(1 downto 0);
		SDOxDI	: in std_logic_vector(1 downto 0);
		SCLKxSO	: out std_logic_vector(1 downto 0);
		
		OutFIFOCntxSO : out std_logic_vector(9 downto 0);
		OutFIFORdReqxSI : in STD_LOGIC ;
		OutFIFOOutDatxDO	: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
		OutFIFOEmptyxSO : out std_logic
	);
	end component;
	
BEGIN

	-- ClkxC <= Clk32InxCI;
	ResetxR <= '0';
	Clk32EnxSO <= '1';
	
	DetPwrxSO <= SRegxDP(3)(2 downto 0);
	SrcPwrxSO <= (others => '1');
	
	
	DebugLEDxSO(0) <= not AcqEnxS;
	DebugLEDxSO(1) <= AcqEnxS;
	DebugLEDxSO(2) <= '1' when unsigned(SRegxDP(1)) > 0 or unsigned(SRegxDP(2)) > 0 else '0';
	DebugLEDxSO(3) <= '0';
	DebugLEDxSO(4) <= '0';
	DebugLEDxSO(5) <= '0';
	

	AcqEnxS <= SRegxDP(0)(0);
	ArduEnxSO <= AcqEnxS;
	
	p_memless_trg : process (AcqEnxS, TrgClkCntxDP, TrgSmpCntxDP, TrgCntxDP)
	begin
		if AcqEnxS = '1' then
			if TrgClkCntxDP < N_TRG_CLK_PERIODS-1 then -- clock counter
				TrgClkCntxDN <= TrgClkCntxDP +1;
			else 
				TrgClkCntxDN <= 0;
			end if;
				
			if TrgClkCntxDP = 0 then -- sample event
				if TrgSmpCntxDP >= N_SMP_PER_TRG -1 then
					TrgSmpCntxDN <= 0;
				else
					TrgSmpCntxDN <= TrgSmpCntxDP +1;
				end if;	
			else
				TrgSmpCntxDN <= TrgSmpCntxDP;
			end if;
			
			if TrgClkCntxDP = 0 and TrgSmpCntxDP = 0 then -- trigger event (every N_SMP_PER_TRG samples)
				if TrgCntxDP >= N_TRG_WRAP-1 then
					TrgCntxDN <= 0;
				else
					TrgCntxDN <= TrgCntxDP +1;
				end if;
			else
				TrgCntxDN <= TrgCntxDP;
			end if;
		
		else
			TrgClkCntxDN <= 0; 
			TrgSmpCntxDN <= N_SMP_PER_TRG -1;
			TrgCntxDN <= N_TRG_WRAP-1;
		end if;
		
		if TrgClkCntxDP < N_TRG_HIGH then -- Arduino triggered every sample
			ArduTrgOutxSO <= '1';
		else
			ArduTrgOutxSO <= '0';
		end if;
		
		if TrgSmpCntxDP <= TrgCntxDP and AcqEnxS = '1' then -- Aux triggered every N_SMP_PER_TRG samples with increasing trigger width
			AuxTrgOutxSO <= '1';
		else
			AuxTrgOutxSO <= '0';
		end if;
	
	end process;
	
--	TrgClkCntxDN <= TrgClkCntxDP +1 when TrgClkCntxDP < N_TRG_CLK_PERIODS-1 else 0;
--	TrgSmpCntxDN <= TrgSmpCntxDP +1 when TrgClkCntxDP else 
--	
--	ArduTrgOutxSO <= '1' when TrgClkCntxDP < N_TRG_HIGH else '0';
	
		

	HostFtdiUARTCTSxSOB  <= '0';
--	HostFtdiUARTDSRxSO  <= '0';
--	HostFtdiUARTDCDxSO  <= '0';

	TxSRegxDN <= '0' when TxSRegClrxS = '1' else
						'1' when TxSRegSetxS = '1' else
						TxSRegxDP;
	


	p_memzing : process (ClkxC, ResetxR)
	begin
      if (rising_edge(ClkxC)) then
         if (ResetxR = '1') then
				ADC_BRD_StatexDP <= sCheck;
				ADC_BRD_IIxDP <= 0;
				ADC_BRD_ByteCntxDP <= 0;
				FromHostStatexDP <= sWait;
				FromHostByteCntxDP <= 0;
				SRegxDP <= (others => (others => '0'));
				TxSRegxDP <= '0';
				TxSRegCntxDP <= 0;
				TrgClkCntxDP <= 0;
				TrgSmpCntxDP <= 0;
				TrgCntxDP <= 0;
         else
				ADC_BRD_StatexDP <= ADC_BRD_StatexDN;
				ADC_BRD_IIxDP <= ADC_BRD_IIxDN;
				ADC_BRD_ByteCntxDP <= ADC_BRD_ByteCntxDN;
				FromHostStatexDP <= FromHostStatexDN;
				FromHostByteCntxDP <= FromHostByteCntxDN;
				SRegxDP <= SRegxDN;
				TxSRegxDP <= TxSRegxDN;
				TxSRegCntxDP <= TxSRegCntxDN;
				TrgClkCntxDP <= TrgClkCntxDN;
				TrgSmpCntxDP <= TrgSmpCntxDN;
				TrgCntxDP <= TrgCntxDN;
         end if;  
      end if;
   end process;


	p_memless_from_opt : process(ADC_BRD_StatexDP, ADC_BRD_IIxDP, ADC_BRD_FIFOEmptyxS, ADC_BRD_FIFOCntxS, ADC_BRD_FIFOPDatxD, ADC_BRD_ByteCntxDP, TxSRegxDP, TxSRegCntxDP, SRegxDP, AUX_FIFOEmptyxS, AUX_FIFOPDatxD, AUX_FIFOCntxS, FromArduFIFOEmptyxS, FromArduFIFOCntxS, FromArduFIFOPDatxD)
	begin
		ADC_BRD_StatexDN <= ADC_BRD_StatexDP;
		ADC_BRD_IIxDN <= ADC_BRD_IIxDP;
		ToHostUARTPDatxD <= std_logic_vector(to_unsigned(ADC_BRD_IIxDP,ToHostUARTPDatxD'length));
		ToHostUARTPDatRdyxS <= '0';
		ADC_BRD_FIFORdAcqxS <= (others => '0'); 
		AUX_FIFORdAcqxS <= '0';
		FromArduFIFORdAcqxS <= '0';
		ADC_BRD_ByteCntxDN <= 0;
		TxSRegClrxS <= '0';
		TxSRegCntxDN <= N_STATUS_REG-1;
		case ADC_BRD_StatexDP is
			when sCheck =>
				if TxSRegxDP = '1' then
					ADC_BRD_StatexDN <= sTx254;
				elsif ADC_BRD_FIFOEmptyxS(ADC_BRD_IIxDP) = '0' and 
					unsigned(ADC_BRD_FIFOCntxS(ADC_BRD_IIxDP)) >= resize(unsigned(ADC_BRD_FIFOPDatxD(ADC_BRD_IIxDP)), ADC_BRD_FIFOCntxS(0)'length)+1 then
					ADC_BRD_StatexDN <= sTxADC_N;
				elsif AUX_FIFOEmptyxS = '0' and
					unsigned(AUX_FIFOCntxS) >= resize(unsigned(AUX_FIFOPDatxD), AUX_FIFOCntxS'length)+1 then
					ADC_BRD_StatexDN <= sTX200;
				elsif FromArduFIFOEmptyxS = '0' and
					unsigned(FromArduFIFOCntxS) >= resize(unsigned(FromArduFIFOPDatxD), FromArduFIFOCntxS'length)+1 then
					ADC_BRD_StatexDN <= sTX201;	
				else
					ADC_BRD_StatexDN <= sNextADC;
				end if;
			when sTxADC_N =>
				ADC_BRD_StatexDN <= sTxData;
				--ToHostUARTPDatxD <= std_logic_vector(to_unsigned(ADC_BRD__IIxDP,ToHostUARTPDatxD'length));
				ToHostUARTPDatRdyxS <= '1';
				ADC_BRD_ByteCntxDN <= to_integer(unsigned(ADC_BRD_FIFOPDatxD(ADC_BRD_IIxDP)));
			when sTxData =>
				if ADC_BRD_ByteCntxDP = 0 then
					ADC_BRD_StatexDN <= sNextADC;
				end if;
				ToHostUARTPDatxD <= ADC_BRD_FIFOPDatxD(ADC_BRD_IIxDP);
				ToHostUARTPDatRdyxS <= '1';
				ADC_BRD_FIFORdAcqxS(ADC_BRD_IIxDP) <= '1';
				if ADC_BRD_ByteCntxDP > 0 then
					ADC_BRD_ByteCntxDN <= ADC_BRD_ByteCntxDP -1;
				end if;
			when sNextADC =>
				ADC_BRD_StatexDN <= sCheck;
				if ADC_BRD_IIxDP < N_ADC-1 then
					ADC_BRD_IIxDN <= ADC_BRD_IIxDP + 1;
				else
					ADC_BRD_IIxDN <= 0;
				end if;
				
			when sTX200 => 
				ADC_BRD_StatexDN <= sTxAUX;
				ToHostUARTPDatRdyxS <= '1';
				ToHostUARTPDatxD <= std_logic_vector(to_unsigned(200,ToHostUARTPDatxD'length));
				ADC_BRD_ByteCntxDN <= to_integer(unsigned(AUX_FIFOPDatxD));
				
			when sTxAUX =>
				if ADC_BRD_ByteCntxDP = 0 then
					ADC_BRD_StatexDN <= sCheck;
				end if;
				ToHostUARTPDatxD <= AUX_FIFOPDatxD;
				ToHostUARTPDatRdyxS <= '1';
				AUX_FIFORdAcqxS <= '1';
				if ADC_BRD_ByteCntxDP > 0 then
					ADC_BRD_ByteCntxDN <= ADC_BRD_ByteCntxDP -1;
				end if;
				
			when sTX201 => --------------------------------------------
				ADC_BRD_StatexDN <= sTxARDU;
				ToHostUARTPDatRdyxS <= '1';
				ToHostUARTPDatxD <= std_logic_vector(to_unsigned(201,ToHostUARTPDatxD'length));
				ADC_BRD_ByteCntxDN <= to_integer(unsigned(FromArduFIFOPDatxD));
				
			when sTxARDU =>
				if ADC_BRD_ByteCntxDP = 0 then
					ADC_BRD_StatexDN <= sCheck;
				end if;
				ToHostUARTPDatxD <= FromArduFIFOPDatxD;
				ToHostUARTPDatRdyxS <= '1';
				FromArduFIFORdAcqxS <= '1'; 
				if ADC_BRD_ByteCntxDP > 0 then
					ADC_BRD_ByteCntxDN <= ADC_BRD_ByteCntxDP -1;
				end if; -------------------------------------------------
				
				
			when sTx254 => -- source announciator for status regs
				ADC_BRD_StatexDN <= sTxSReg;
				ToHostUARTPDatRdyxS <= '1';
				ToHostUARTPDatxD <= std_logic_vector(to_unsigned(254,ToHostUARTPDatxD'length));
				TxSRegCntxDN <= N_STATUS_REG-1;
				TxSRegClrxS <= '1';
			
			when sTxSReg =>
				if TxSRegCntxDP = 0 then
					ADC_BRD_StatexDN <= sTxFiller;
					TxSRegCntxDN <= N_BYTES_PER_SAMPLE - N_STATUS_REG -1-1;
				else
					TxSRegCntxDN <= TxSRegCntxDP -1;
				end if;
				ToHostUARTPDatRdyxS <= '1';
				ToHostUARTPDatxD <= SRegxDP(TxSRegCntxDP);
				
			when sTxFiller =>
				if TxSRegCntxDP = 0 then
					ADC_BRD_StatexDN <= sCheck;
				else
					TxSRegCntxDN <= TxSRegCntxDP -1;
				end if;
				ToHostUARTPDatRdyxS <= '1';
				ToHostUARTPDatxD <= std_logic_vector(to_unsigned(172,ToHostUARTPDatxD'length));
				
			when others =>
				ADC_BRD_StatexDN <= sCheck;
		end case;	
   end process;
	
	
	ADC_BRD_ENG_insts : for I in 0 to N_ADC-1 generate
		ADC_BRD_ENG_inst : ADC_BRD_ENG
			PORT map(
				ClkInxCI => ClkxC,
				ResetxRI => ResetxR,
				AcqEnxSI => AcqEnxS,
				
				ADC_SDOxDI => EXP_SDOxDI(I),
				ADC_SCKxSO => EXP_SCKxD(I),
				ADC_CNVxSO => EXP_CNVxDO(I),
				
				OutFIFOCntxSO => ADC_BRD_FIFOCntxS(I),
				OutFIFORdReqxSI => ADC_BRD_FIFORdAcqxS(I),
				OutFIFOOutDatxDO	=> ADC_BRD_FIFOPDatxD(I),
				OutFIFOEmptyxSO => ADC_BRD_FIFOEmptyxS(I)
				);
	end generate ADC_BRD_ENG_insts;
	
	EXP_SCKxDO(0) <= EXP_SCKxD(0);
	EXP_SCKxDO(1) <= EXP_SCKxD(6);
	
	
	host_ftdi_uart_tx_host_inst : UART_TX_HOST
		generic map(
			TX_CLK_DIV => 8
		)
		port map (
			ClkxCI 	 => UARTClkxC,
			FIFOClkxCI => ClkxC,
			ResetxRI => ResetxR,
			CTSxSIB	=> HostFtdiUARTRTSxSIB,
			TxOutxDO => HostFtdiUARTTxxDO,
			FIFOFullxSO => open,
			FIFOWrEnxSI => ToHostUARTPDatRdyxS,
			FIFOPDatxDI => ToHostUARTPDatxD,
			FIFOCntxSO => open --ToHostUARTFIFOCntxS
		);
		
		
	p_memless_from_host : process(FromHostStatexDP, FromHostFIFOEmptyxS, FromHostFIFOPDatxD, FromHostByteCntxDP, FromHostFIFOCntxS, SRegxDP)
	begin
		FromHostStatexDN <= FromHostStatexDP;
		FromHostFIFORdAcqxS <= '0'; 
		FromHostByteCntxDN <= FromHostByteCntxDP;
		SRegxDN(0 to N_WRITABLE_SREG-1) <= SRegxDP(0 to N_WRITABLE_SREG-1); 
		SRegxDN(N_WRITABLE_SREG to N_STATUS_REG-1) <= (others => (others => '0'));
		TxSRegSetxS <= '0';
		case FromHostStatexDP is
			when sWait =>
				if FromHostFIFOEmptyxS = '0' then
					if unsigned(FromHostFIFOPDatxD) /= to_unsigned(254,FromHostFIFOPDatxD'length) then
						-- flush
						FromHostFIFORdAcqxS <= '1';
					elsif unsigned(FromHostFIFOPDatxD) = to_unsigned(254,FromHostFIFOPDatxD'length) and 
						unsigned(FromHostFIFOCntxS) >= to_unsigned(N_STATUS_REG + 1, FromHostFIFOCntxS'length) then
						-- update
						FromHostFIFORdAcqxS <= '1';
						FromHostStatexDN <= sRxData;
					end if;
				end if;
				FromHostByteCntxDN <= N_STATUS_REG-1;
			when sRxData =>
				if FromHostByteCntxDP = 0 then
					FromHostStatexDN <= sWait;
					TxSRegSetxS <= '1';
				end if;
				FromHostFIFORdAcqxS <= '1';
				if FromHostByteCntxDP <= (N_WRITABLE_SREG-1) then
					SRegxDN(FromHostByteCntxDP) <= FromHostFIFOPDatxD;
				end if;
				if FromHostByteCntxDP > 0 then
					FromHostByteCntxDN <= FromHostByteCntxDP -1;
				end if;
				
			when others =>
				FromHostStatexDN <= sWait;
		end case;	
   end process;
		
	host_ftdi_uart_rx_inst : uart_rx 
	generic map(
		RX_CLK_DIV => 8
		)
	port map(
		ClkxCI => UARTClkxC,
		FIFOClkxCI => ClkxC,
		ResetxRI => ResetxR,
		RxInxDI	=> HostFtdiUARTRxxDI,
		FIFOPDatxDO => FromHostFIFOPDatxD,
		FIFOEmptyxSO => FromHostFIFOEmptyxS,
		FIFOFullxSO => open,
		FIFOCntxSO => FromHostFIFOCntxS,
		FIFORdAcqxSI => FromHostFIFORdAcqxS
	);
	
	ardu_uart_rx_inst : uart_rx 
	generic map(
		RX_CLK_DIV => 16
		)
	port map(
		ClkxCI => ClkxC,
		FIFOClkxCI => ClkxC,
		ResetxRI => ResetxR,
		RxInxDI	=> ArduUARTRxxDI,
		FIFOPDatxDO => FromArduFIFOPDatxD,
		FIFOEmptyxSO => FromArduFIFOEmptyxS,
		FIFOFullxSO => open,
		FIFOCntxSO => FromArduFIFOCntxS,
		FIFORdAcqxSI => FromArduFIFORdAcqxS
	);

	LED_MOD_insts : for I in 0 to N_SRC_OPTODES-1 generate
		LED730_MOD_inst : LED_MOD
		PORT map(
			ClkxCI => ClkxC,
			ResetxRI => ResetxR,
			LEDEnxSI => SRegxDP(1)(I),
			SClrxSI	=> '0',
			FreqSelxDI => std_logic_vector(to_unsigned(2*(I+1)-1,5)),
			ModOutxSO => LED730xDO(I)
		);
		
		LED850_MOD_inst : LED_MOD
		PORT map(
			ClkxCI => ClkxC,
			ResetxRI => ResetxR,
			LEDEnxSI => SRegxDP(2)(I),
			SClrxSI	=> '0',
			FreqSelxDI => std_logic_vector(to_unsigned(2*(I+1),5)),
			ModOutxSO => LED850xDO(I)
		);
	end generate LED_MOD_insts;
	
	LED730xDO(LED730xDO'left downto N_SRC_OPTODES) <= (others => '0');
	LED850xDO(LED730xDO'left downto N_SRC_OPTODES) <= (others => '0');
	LEDhighxDO <= (others => SRegxDP(0)(1));
	
	MainPLL_inst : MainPLL
		port map	(
			areset => ResetxR,
			inclk0 => Clk32InxCI,
			c0	=> UARTClkxC,
			c1 => ClkxC,
			locked => PLLLockedxS 
		);
		

	AUX_ADC_RX_inst : AUX_ADC_RX
		port map(
			ClkxCI => ClkxC,
			ResetxRI => ResetxR,
			SClrxSI => '0',
			AcqEnxSI => AcqEnxS,
			
			CSnxSO => AUX_CSnxSO,
			SDOxDI => AUX_SDOxDI,
			SCLKxSO => AUX_SCLKxSO,
			
			OutFIFOCntxSO => AUX_FIFOCntxS,
			OutFIFORdReqxSI => AUX_FIFORdAcqxS,
			OutFIFOOutDatxDO => AUX_FIFOPDatxD,
			OutFIFOEmptyxSO => AUX_FIFOEmptyxS
		);
		
END ControlCard00_00_behavior;