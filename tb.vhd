-- File:        tb.vhd
-- Author:      Richard James Howe
-- Repository:  https://github.com/howerj/subleq-vhdl
-- Email:       howe.r.j.89@gmail.com
-- License:     MIT
-- Description: Test bench for top level entity

library ieee, work, std;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use work.util.all;
use std.textio.all;
use work.uart_pkg.all;

entity tb is
end tb;

architecture testing of tb is
	constant g:                        common_generics  := default_settings;
	constant clock_period:             time             := 1000 ms / g.clock_frequency;
	constant baud:                     positive         := 115200;
	constant configuration_file_name:  string           := "tb.cfg";
	constant subleq_image_hex_file:    string           := "subleq.hex";
	--constant subleq_image_hex_file:    string           := "hi.hex";
	--constant subleq_image_hex_file:    string           := "hello.hex";
	constant N:                        positive         := 16;

	signal stop:   boolean    := false;
	signal clk:    std_ulogic := '0';
	signal halt:   std_ulogic := '0';
	signal rst:    std_ulogic := '1';

	signal tx: std_ulogic := 'X';
	signal rx: std_ulogic := '1';

	type configurable_items is record
		clocks:         natural;
		forever:        boolean;
		debug:          natural;
	end record;

	function set_configuration_items(ci: configuration_items) return configurable_items is
		variable r: configurable_items;
	begin
		r.clocks         := ci(0).value;
		r.forever        := ci(1).value > 0;
		r.debug          := ci(2).value;
		return r;
	end function;

	constant configuration_default: configuration_items(0 to 2) := (
		(name => "Clocks..", value => 1000),
		(name => "Forever.", value => 0),
		(name => "Debug...", value => 0) -- N.B. Doesn't work for setting generics
	);

	-- Test bench configurable options --

	shared variable cfg: configurable_items := set_configuration_items(configuration_default);
	signal configured: boolean := false;
begin
	-- A more advanced test bench would hook the `rx`/`tx`
	-- lines up to a UART which could be connected up to
	-- stdin/stdout, or more realistically we could look
	-- for a startup string from the CPU and halt the 
	-- simulation when it has been received, or send
	-- a command to halt the CPU which it has to process.
	uut: entity work.top
		generic map(
			g          => g,
			file_name  => subleq_image_hex_file,
			N          => N,
			baud       => baud,
			debug      => cfg.debug)
		port map (
			clk  => clk,
--			rst  => rst,
			halt => halt,
			tx   => tx,
			rx   => rx);

	clock_process: process
		variable count: integer := 0;
		variable aline: line;
	begin
		stop <= false;
		wait until configured;
		wait for clock_period;
		-- N.B. We could add clock jitter if we wanted, however we would
		-- probably also want to add it to each of the modules clocks, along
		-- with an adjustable delay.
		while (count < cfg.clocks or cfg.forever)  and halt = '0' loop
			clk <= '1';
			wait for clock_period / 2;
			clk <= '0';
			wait for clock_period / 2;
			count := count + 1;
		end loop;
		if halt = '1' then
			write(aline, string'("{HALT}"));
		else
			write(aline, string'("{CYCLES}"));
		end if;

		if cfg.debug > 0 then
			writeline(OUTPUT, aline);
		end if;

		stop <= true;
		report "Clock process end";
		wait;
	end process;

	stimulus_process: process
		variable configuration_values: configuration_items(configuration_default'range) := configuration_default;
	begin
		-- write_configuration_tb(configuration_file_name, configuration_default);
		read_configuration_tb(configuration_file_name, configuration_values);
		cfg := set_configuration_items(configuration_values);
		configured <= true;

		rst <= '1';
		wait for clock_period;
		rst <= '0';

		configured <= true;
		while not stop loop
			wait for clock_period;
		end loop;
		report "Stimulus Process end";
		wait;
	end process;
end architecture;
