library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use STD.textio.all;
use ieee.std_logic_textio.all;

entity DFT_ENG_tb is
end DFT_ENG_tb;

architecture DFT_ENG_tb of DFT_ENG_tb is

	signal sim_finished : boolean := false;
  	file file_VECTORS : text;
  	file file_RESULTS : text;

	signal ClkxC : std_logic;
	signal DataSClrxS : std_logic;
	
	signal ADCDataxD : std_logic_vector(23 downto 0);
	signal ADCSmpsAvxD : std_logic_vector(10 downto 0);
	
	signal ADCDataRdReqxS : std_logic;
	signal DFTOutFIFOCntxS : std_logic_vector(7 downto 0);
	signal DFTOutFIFORdReqxS  : std_logic;
	signal DFTOutFIFODatxD	: STD_LOGIC_VECTOR(35 DOWNTO 0);
	
	constant CLK_PERIOD : time := 100 ns;
	constant DELTA_T : time := CLK_PERIOD/100;

	component DFT_ENG
		port (
			ClkxCI 	 : in std_logic;
			ResetxRI : in std_logic;
			
			RawDatxDI : in std_logic_vector(23 downto 0);
			RawDatCntxDI : in std_logic_vector(10 downto 0);
			RawDatRdReqxSO : out std_logic;
			
			OutFIFOCntxSO : out std_logic_vector(7 downto 0);
			OutFIFORdReqxSI : in STD_LOGIC ;
			OutFIFODatxDO	: OUT STD_LOGIC_VECTOR (35 DOWNTO 0)
		
		--OutFIFOEmptyxSO : out std_logic;
			
		);
	end component;

begin

	reset_process : process
	begin
		wait for 1 ns;
		DataSClrxS <= '1';
		wait for 200 ns;
		DataSClrxS <= '0';
		wait;
	end process reset_process;
	

	clock_process : process
	begin
		if not sim_finished then
			ClkxC <= '0';
			wait for CLK_PERIOD/2;
			ClkxC <= '1';
			wait for CLK_PERIOD/2;
		else 
			wait;
		end if;
	end process clock_process;

	input_vectors_process : process
		variable v_ILINE : line;
		variable v_IDATA : std_logic_vector(ADCDataxD'range);
	begin
		file_open(file_VECTORS, "input_vectors.txt",  read_mode);
		ADCSmpsAvxD <= std_logic_vector(to_unsigned(1100,ADCSmpsAvxD'length));

		while not endfile(file_VECTORS) loop
			if ADCDataRdReqxS = '1' then
				wait until rising_edge(ClkxC);
				wait for DELTA_T;
				readline(file_VECTORS, v_ILINE);
				read(v_ILINE, v_IDATA);
				ADCDataxD <= v_IDATA;
			else
				wait for DELTA_T;
			end if;
		end loop;

		file_close(file_VECTORS);
		ADCSmpsAvxD <= std_logic_vector(to_unsigned(0,ADCSmpsAvxD'length));
		wait;	
	end process input_vectors_process; 
	
	output_vectors_process : process
		variable v_ILINE : line;
		variable v_OLINE : line;
		variable v_IDATA : std_logic_vector(ADCDataxD'range);
		variable v_ODATA : std_logic_vector(DFTOutFIFODatxD'range);
	begin
		file_open(file_RESULTS, "output_results.txt", write_mode);
		while true loop
			if unsigned(DFTOutFIFOCntxS) > 0 then
				DFTOutFIFORdReqxS <= '1';
				wait until rising_edge(ClkxC);
				wait for DELTA_T;
				write(v_OLINE, DFTOutFIFODatxD, right, DFTOutFIFODatxD'length);
				writeline(file_RESULTS, v_OLINE);
			else
				DFTOutFIFORdReqxS <= '0';
				wait for DELTA_T;
			end if;
		end loop;

		file_close(file_RESULTS);

		wait;	
	end process output_vectors_process; 
	
	--ADCDataxD <= std_logic_vector(to_unsigned(1000,ADCDataxD'length));
	-- ADCSmpsAvxD <= std_logic_vector(to_unsigned(300,ADCSmpsAvxD'length));
	--DFTOutFIFORdReqxS <= not DFTOutFIFOEmptyxS;

	DFT_ENG_inst : DFT_ENG 
		port map(
			ClkxCI 	=> ClkxC,
			ResetxRI => DataSClrxS,
			
			RawDatxDI => ADCDataxD,	--: in std_logic_vector(23 downto 0);
			RawDatCntxDI => ADCSmpsAvxD,		--: in std_logic_vector(8 downto 0);
			RawDatRdReqxSO => ADCDataRdReqxS,	--: out std_logic
			
			OutFIFOCntxSO => DFTOutFIFOCntxS,--: out std_logic
			OutFIFORdReqxSI => DFTOutFIFORdReqxS,	--: in STD_LOGIC ;
			OutFIFODatxDO => DFTOutFIFODatxD	--: OUT STD_LOGIC_VECTOR (35 DOWNTO 0)
			
		);

end DFT_ENG_tb;