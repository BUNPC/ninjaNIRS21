-- Bernhard Zimmermann - bzim@bu.edu
-- Boston University Neurophotonics Center
-- June 2021

-- Interface for ADS7886

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity AUX_ADC_RX is
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
end AUX_ADC_RX;

architecture Behavioral of AUX_ADC_RX is
	constant CLK_PERIODS_PER_CONV : integer := 315*4;
	constant CLK_PERIODS_PER_SCK : integer := 16;
	constant N_BYTES_PER_SAMPLE : integer := 95;
	constant N_FPGA_CONV_AVG : integer := 512;
	constant N_ADC : integer := 2;
	
	signal ClkCntxDP, ClkCntxDN	: integer range 0 to CLK_PERIODS_PER_CONV-1;
	signal SckClkCntxDP, SckClkCntxDN: integer range 0 to CLK_PERIODS_PER_SCK-1;
	signal ConvCntxDP, ConvCntxDN	: integer range 0 to N_FPGA_CONV_AVG;
	signal BitsCntxDP, BitsCntxDN	: integer range 0 to 15;
	signal SmpCntxDP, SmpCntxDN : integer range 0 to 255; 
	Signal ByteCntxDP, ByteCntxDN : integer range 0 to N_BYTES_PER_SAMPLE-1;
	
	type fsmstatetype is (sCShigh, sPostCShigh, sSCLKlow, sAcq, sSCLKhigh, sReadComplete, sFIFOWriteByteCnt, sFIFOWriteSmpCnt, sFIFOWriteLowByte, sFIFOWriteHighByte, sFIFOWriteFiller, sIdle);
	signal StatexDP, StatexDN : fsmstatetype;	
	attribute syn_encoding : string;
	attribute syn_encoding of fsmstatetype : type is "safe";
	
	signal ADCCntxDP, ADCCntxDN : integer range 0 to N_ADC-1;
	
	type AUX_ADC_SReg_Array_Type is array (0 to N_ADC-1) of unsigned(11 downto 0);
	signal ADCSregxDP, ADCSregxDN : AUX_ADC_SReg_Array_Type;
	type AUX_ADC_Acc_Array_Type is array (0 to N_ADC-1) of unsigned(20 downto 0);
	signal ADCAccxDP, ADCAccxDN : AUX_ADC_Acc_Array_Type;
	
	signal FIFOWrReqxS : std_logic;
	signal PDataxD : std_logic_vector(7 downto 0);
	
	signal SCLKxS : std_logic;
	signal CSnxS : std_logic;
	
	
	COMPONENT AUX_ADC_RX_FIFO
	PORT(
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
	END COMPONENT;
	

begin
	SCLKxSO <= (others => SCLKxS);
	CSnxSO <= (others => CSnxS);
	
	p_memzing : process (ClkxCI, ResetxRI)
	begin
      if (rising_edge(ClkxCI)) then
         if (ResetxRI = '1') then
				ClkCntxDP <= 0;
				SckClkCntxDP <= 0;
				ConvCntxDP <= 0;
				StatexDP <= sCShigh;
				BitsCntxDP <= 0;
				ADCAccxDP <= (others => (others => '0'));
				ADCCntxDP <= 0;
				SmpCntxDP <= 0;
         else
				ClkCntxDP <= ClkCntxDN;
				SckClkCntxDP <= SckClkCntxDN;
				ConvCntxDP <= ConvCntxDN;
				StatexDP <= StatexDN;
				BitsCntxDP <= BitsCntxDN;
				ADCAccxDP <= ADCAccxDN;
				ADCCntxDP <= ADCCntxDN;
				SmpCntxDP <= SmpCntxDN;
         end if;   
			ADCSregxDP <= ADCSregxDN;
			ByteCntxDP <= ByteCntxDN;
      end if;
   end process;
   
	p_memless_out_decode : process(StatexDP, ClkCntxDP, SckClkCntxDP, BitsCntxDP, ConvCntxDP, SDOxDI, ADCAccxDP, ADCSregxDP, SmpCntxDP, ADCCntxDP, ByteCntxDP, AcqEnxSI)
	begin
		CSnxS <= '0';
		SCLKxS <= '1';
		FIFOWrReqxS <= '0';
		ClkCntxDN <= ClkCntxDP+1;
		SckClkCntxDN <= 0;
		ADCAccxDN <= ADCAccxDP;
		ADCSregxDN <= ADCSregxDP;
		BitsCntxDN <= BitsCntxDP;
		ConvCntxDN <= ConvCntxDP;
		ADCCntxDN <= 0;
		SmpCntxDN <= SmpCntxDP;
		ByteCntxDN <= 0;
		PDataxD <= std_logic_vector(to_unsigned(170,8));
		case StatexDP is
			when sCShigh =>
				CSnxS <= '1';
				BitsCntxDN <= 0;
				if SckClkCntxDP < CLK_PERIODS_PER_SCK-1 then
					SckClkCntxDN <= SckClkCntxDP +1;
				end if;
			when sPostCShigh =>
			when sSCLKlow =>
				SCLKxS <= '0';
				if SckClkCntxDP < (CLK_PERIODS_PER_SCK/2)-2 then
					SckClkCntxDN <= SckClkCntxDP +1;
				end if;
			when sAcq =>
				SCLKxS <= '0';
				if BitsCntxDP >= 3 and BitsCntxDP <= 14 then
					for I in 0 to N_ADC-1 loop
						ADCSregxDN(I) <= shift_left(ADCSregxDP(I),1);
						ADCSregxDN(I)(0) <= SDOxDI(I);
					end loop;
				end if;
				BitsCntxDN <= BitsCntxDP +1;
			when sSCLKhigh =>
				if SckClkCntxDP < (CLK_PERIODS_PER_SCK/2)-1 then
					SckClkCntxDN <= SckClkCntxDP +1;
				end if;
				
			when sReadComplete =>
				for I in 0 to N_ADC-1 loop
					ADCAccxDN(I) <= ADCAccxDP(I) + resize(ADCSregxDP(I),ADCAccxDP(I)'length);
				end loop;
				ConvCntxDN <= ConvCntxDP +1;
				BitsCntxDN <= 0;
				
			when sFIFOWriteByteCnt =>
				PDataxD <= std_logic_vector(to_unsigned(N_BYTES_PER_SAMPLE-2,8));
				FIFOWrReqxS <= '1';
			
			when sFIFOWriteSmpCnt =>
				SmpCntxDN <= (SmpCntxDP +1) mod 256;
				PDataxD <= std_logic_vector(to_unsigned((SmpCntxDP mod 256),8));
				FIFOWrReqxS <= '1';
								
			when sFIFOWriteLowByte =>
				FIFOWrReqxS <= '1';
				PDataxD <= std_logic_vector(ADCAccxDP(ADCCntxDP)(12 downto 5));
				ADCCntxDN <= ADCCntxDP;
				
			when sFIFOWriteHighByte =>
				FIFOWrReqxS <= '1';
				PDataxD <= std_logic_vector(ADCAccxDP(ADCCntxDP)(20 downto 13));
				if ADCCntxDP < N_ADC-1 then
					ADCCntxDN <= ADCCntxDP +1;
				end if;
			
			when sFIFOWriteFiller =>
				FIFOWrReqxS <= '1';
				PDataxD <= std_logic_vector(to_unsigned(171,8));
				ByteCntxDN <= ByteCntxDP +1;
				ADCAccxDN <= (others => (others => '0'));
				ConvCntxDN <= 0;
								
			when sIdle =>
				CSnxS <= '1';
				BitsCntxDN <= 0;
				--ADCAccxDN <= (others => (others => '0'));
				if ClkCntxDP >= CLK_PERIODS_PER_CONV-1 then
					ClkCntxDN <= 0;
				end if;
				if AcqEnxSI = '0' then
					SmpCntxDN <= 0;
				end if;
								
			when others =>
		end case;
   end process;
   
	p_memless_next_state_decode : process (StatexDP, BitsCntxDP, ClkCntxDP, SckClkCntxDP, ConvCntxDP, ADCCntxDP, ByteCntxDP, AcqEnxSI)
	begin
		StatexDN <= StatexDP;
		case StatexDP is
			when sCShigh =>
				if SckClkCntxDP >= CLK_PERIODS_PER_SCK-1 then
					StatexDN <= sPostCShigh;
				end if;
			when sPostCShigh =>
				StatexDN <= sSCLKlow;
			when sSCLKlow =>
				if SckClkCntxDP >= (CLK_PERIODS_PER_SCK/2)-2 then
					StatexDN <= sAcq;
				end if;
			when sAcq =>
				StatexDN <= sSCLKhigh;
			when sSCLKhigh =>
				if BitsCntxDP >= 15 then
					StatexDN <= sReadComplete;
				elsif SckClkCntxDP >= (CLK_PERIODS_PER_SCK/2)-1 then
					StatexDN <= sSCLKlow;
				end if;

			when sReadComplete =>
				if ConvCntxDP >= N_FPGA_CONV_AVG-1 then
					StatexDN <= sFIFOWriteByteCnt;
				else
					StatexDN <= sIdle;
				end if;
				
			when sFIFOWriteByteCnt =>
				StatexDN <= sFIFOWriteSmpCnt;
			
			when sFIFOWriteSmpCnt =>
				StatexDN <= sFIFOWriteLowByte;
				
			when sFIFOWriteLowByte =>
				StatexDN <= sFIFOWriteHighByte;
				
			when sFIFOWriteHighByte =>
				if ADCCntxDP < N_ADC-1 then
					StatexDN <= sFIFOWriteLowByte;
				else
					StatexDN <= sFIFOWriteFiller;
				end if;
				
			when sFIFOWriteFiller =>
				if ByteCntxDP >= N_BYTES_PER_SAMPLE - (2 * N_ADC) -3 -1 then
					StatexDN <= sIdle;
				end if;
				
			when sIdle =>
				if ClkCntxDP >= CLK_PERIODS_PER_CONV-1 and AcqEnxSI = '1' then
					StatexDN <= sCShigh;
				end if;
				
			when others =>
				StatexDN <= sIdle;
		end case;	
   end process;

	AUX_ADC_RX_FIFO_inst : AUX_ADC_RX_FIFO 
	PORT MAP (
		clock	 => ClkxCI,
		data	 => PDataxD,
		rdreq	 => OutFIFORdReqxSI,
		sclr	 => SClrxSI,
		wrreq	 => FIFOWrReqxS,
		empty	 => OutFIFOEmptyxSO,
		full	 => open,
		q	 	 => OutFIFOOutDatxDO,
		usedw	 => OutFIFOCntxSO
	);
end Behavioral;
