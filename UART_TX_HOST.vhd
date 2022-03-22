-- Bernhard Zimmermann - bzim@bu.edu
-- Boston University Neurophotonics Center
-- June 2021


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity UART_TX_HOST is
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
end UART_TX_HOST;

architecture Behavioral of UART_TX_HOST is
	--constant TX_CLK_DIV : integer := 7;
	--constant TX_CLK_STOP_TICKS : integer := FMAX(TX_CLK_DIV-5,0);

	type fsmstatetype is (sIdle, sWait1, sWait2, sRead, sTxStart, sTxBits, sTxStop);
	signal StatexDP, StatexDN : fsmstatetype;
	--signal ParDatxDP, ParDatxDN : std_logic_vector(7 downto 0);
	signal FIFORdEnxS, FIFOEmptyxS : std_logic;
	signal FIFODataxD : std_logic_vector(7 downto 0);
	signal PDRegxDP, PDRegxDN  : std_logic_vector(7 downto 0);
	
	signal ClkCntxDP, ClkCntxDN : integer range 0 to TX_CLK_DIV-1;
	signal BitCntxDP, BitCntxDN: integer range 0 to 7;
	
	signal FIFOCntxS : std_logic_vector(14 downto 0);

	COMPONENT UART_TX_HOST_FIFO
		PORT
		(
			aclr		: IN STD_LOGIC  := '0';
			data		: IN STD_LOGIC_VECTOR (7 DOWNTO 0);
			rdclk		: IN STD_LOGIC ;
			rdreq		: IN STD_LOGIC ;
			wrclk		: IN STD_LOGIC ;
			wrreq		: IN STD_LOGIC ;
			q		: OUT STD_LOGIC_VECTOR (7 DOWNTO 0);
			rdempty		: OUT STD_LOGIC ;
			wrfull		: OUT STD_LOGIC ;
			wrusedw		: OUT STD_LOGIC_VECTOR (14 DOWNTO 0)
		);
	END COMPONENT;
	
begin

	p_memzing : process (ClkxCI, ResetxRI)
	begin
      if (rising_edge(ClkxCI)) then
         if (ResetxRI = '1') then
			StatexDP <= sIdle;
         else
			StatexDP <= StatexDN;
         end if;  
		 ClkCntxDP <= ClkCntxDN;
		 BitCntxDP <= BitCntxDN;
		 PDRegxDP <= PDRegxDN;
      end if;
   end process;
   
	p_memless_out_decode : process(StatexDP, ClkCntxDP, BitCntxDP, PDRegxDP, FIFODataxD)
	begin
		ClkCntxDN <= ClkCntxDP +1;
		BitCntxDN <= BitCntxDP;
		TxOutxDO <= '1';
		FIFORdEnxS <= '0';
		PDRegxDN <= PDRegxDP;
		case StatexDP is
			when sIdle =>
			when sWait1 =>
			when sWait2 =>
			when sRead => 
				ClkCntxDN <= 0;
				FIFORdEnxS <= '1';
			when sTxStart =>
				PDRegxDN <= FIFODataxD;
				TxOutxDO <= '0';
				if ClkCntxDP = TX_CLK_DIV-1 then
					ClkCntxDN <= 0;
					BitCntxDN <= 0;
				end if;
			when sTxBits =>
				TxOutxDO <= PDRegxDP(BitCntxDP);
				if ClkCntxDP = TX_CLK_DIV-1 then
					ClkCntxDN <= 0;
					BitCntxDN <= BitCntxDP +1;
				end if;
			when sTxStop =>
				if ClkCntxDP = TX_CLK_DIV-1 then
					ClkCntxDN <= 0;
				end if;
			when others =>
		end case;
   end process;
   
	p_memless_next_state_decode : process (StatexDP, FIFOEmptyxS, ClkCntxDP, BitCntxDP, CTSxSIB)
	begin
		StatexDN <= StatexDP;
		case StatexDP is
			when sIdle =>
				if FIFOEmptyxS = '0' and CTSxSIB = '0' then
					StatexDN <= sWait1;
				end if;
			when sWait1 =>
				StatexDN <= sWait2;
			when sWait2 =>
				StatexDN <= sRead;
			when sRead => 
				StatexDN <= sTxStart;
			when sTxStart =>
				if ClkCntxDP = TX_CLK_DIV-1 then
					StatexDN <= sTxBits;
				end if;
			when sTxBits =>
				if ClkCntxDP = TX_CLK_DIV-1 and BitCntxDP = 7 then
					StatexDN <= sTxStop;
				end if;
			when sTxStop =>
				if ClkCntxDP = TX_CLK_DIV-1 then
					StatexDN <= sIdle;
				end if;
			when others =>
		end case;	
   end process;

	UART_TX_HOST_FIFO_inst: UART_TX_HOST_FIFO 
	PORT MAP(
		aclr		=> ResetxRI,
		data		=> FIFOPDatxDI,
		rdclk		=> ClkxCI,
		rdreq		=> FIFORdEnxS,
		wrclk		=> FIFOClkxCI,
		wrreq		=> FIFOWrEnxSI,
		q			=> FIFODataxD,
		rdempty	=> FIFOEmptyxS,
		wrfull	=> FIFOFullxSO,
		wrusedw	=> FIFOCntxS
	);
	
	FIFOCntxSO(14 downto 0) <= FIFOCntxS;
	FIFOCntxSO(15) <= '0';

end Behavioral;