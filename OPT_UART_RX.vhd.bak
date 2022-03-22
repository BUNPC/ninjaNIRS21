LIBRARY ieee;
USE ieee.std_logic_1164.all;
--use IEEE.NUMERIC_STD.ALL;


ENTITY UART_RX IS 
	GENERIC(
		RX_CLK_DIV : integer := 4
		); 
	PORT(
		ClkxCI : IN STD_LOGIC;
		ResetxRI : IN STD_LOGIC;
		RxInxDI	: IN STD_LOGIC;
		PDatxDO	: OUT STD_LOGIC_VECTOR(7 downto 0);
		PDatRdyxSO : OUT STD_LOGIC
		);
END UART_RX;

ARCHITECTURE behavioral OF UART_RX IS
	--constant RX_CLK_DIV : integer := 4;
	constant START_BIT_CLKS : integer := (RX_CLK_DIV * 3 / 2)-2;

	type fsmstatetype is (sIdle, sStart, sRead, sPDRdy, sStop);
	signal StatexDP, StatexDN : fsmstatetype;	
	attribute syn_encoding : string;
	attribute syn_encoding of fsmstatetype : type is "safe";

	signal PDatSRegxDP, PDatSRegxDN : STD_LOGIC_VECTOR(7 downto 0);
	
	signal ClkCntxDP, ClkCntxDN : integer range 0 to START_BIT_CLKS;
	signal BitCntxDP, BitCntxDN: integer range 0 to 7;

BEGIN

	PDatxDO <= PDatSRegxDP;

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
	--		PDatORegxDP <= PDatORegxDN;
			PDatSRegxDP <= PDatSRegxDN;
      end if;
   end process;

	p_memless_out_decode : process(StatexDP, ClkCntxDP, BitCntxDP, PDatSRegxDP, RxInxDI)
	begin
		ClkCntxDN <= ClkCntxDP -1;
		BitCntxDN <= BitCntxDP;
		PDatSRegxDN <= PDatSRegxDP;
		PDatRdyxSO <= '0';
		case StatexDP is
			when sIdle =>
			when sStart =>
				ClkCntxDN <= START_BIT_CLKS;
				BitCntxDN <= 7;
			when sRead =>
				if ClkCntxDP = 0 then
					ClkCntxDN <= RX_CLK_DIV -1;
					BitCntxDN <= BitCntxDP -1;
					PDatSRegxDN(7) <= RxInxDI;
					PDatSRegxDN(6 downto 0) <= PDatSRegxDP(7 downto 1);
				end if;
			when sPDRdy =>
				PDatRdyxSO <= '1';
			when sStop =>
			when others =>
		end case;
   end process;

	p_memless_next_state_decode : process (StatexDP, RxInxDI, ClkCntxDP, BitCntxDP)
	begin
		StatexDN <= StatexDP;
		case StatexDP is
			when sIdle =>
				if RxInxDI = '0' then 
					StatexDN <= sStart;
				end if;
			when sStart =>
				StatexDN <= sRead;
			when sRead =>
				if ClkCntxDP = 0 and BitCntxDP = 0 then
					StatexDN <= sPDRdy;
				end if;
			when sPDRdy =>
				StatexDN <= sStop;
			when sStop =>
				if ClkCntxDP = 0 then
					StatexDN <= sIdle;
				end if;
			when others =>
				StatexDN <= sIdle;
		end case;	
   end process;

END behavioral;