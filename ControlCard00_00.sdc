create_clock -period 31.25ns [get_ports Clk32InxCI]
#create_clock -period 24.802ns [get_ports Clk40InxCI]
derive_clock_uncertainty
derive_pll_clocks