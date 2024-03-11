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
	-- With the GHDL simulator these generics can be overridden with
	-- the following syntax:
	--
	-- 	ghdl -r tb '-gbaud=9600' '-ggenerate_non_io_tb=true'
	--
	generic (
		baud:               positive := 115200;
		generate_uart_tbs:  boolean  := false; -- Generate UART test benches as well?
		generate_non_io_tb: boolean  := false -- Do not generate UART, talk directly to `system.vhd` which is faster
	);
end tb;

architecture testing of tb is
	constant g:                       common_generics := default_settings;
	constant clock_period:            time     := 1000 ms / g.clock_frequency;
	constant clks_per_bit:            integer  := g.clock_frequency / baud;
	constant bit_period:              time     := clks_per_bit * clock_period;
	constant N:                       positive := 16;
	constant configuration_file_name: string   := "tb.cfg";
	constant program_file_name:       string   := "subleq.dec";
	--constant program_file_name:       string := "progs/hi.dec";
	--constant program_file_name:       string := "progs/hello.dec";
	--constant program_file_name:       string := "progs/echo.dec";
	--constant program_file_name:       string := "progs/hi2.dec";

	signal stop:   boolean    := false;
	signal clk:    std_ulogic := '0';
	signal halted, blocked: std_ulogic := 'X';
	signal rst:    std_ulogic := '1';
	signal saw_char: boolean := false;

	signal tx_data, rx_data: std_ulogic_vector(7 downto 0) := (others => '0');
	signal io_re, rx_hav: std_ulogic := 'X';
	signal ihav, obsy: std_ulogic := '0';
	signal tx, rx:  std_ulogic := '1';

	-- Test bench configurable options --

	type configurable_items is record
		clocks:         natural;
		forever:        boolean;
		debug:          natural;
		interactive:    natural;
		input_wait_for: time;
		report_uart:    boolean;
		report_number:  natural;
		input_single_line: boolean;
		uart_char_delay: time;
	end record;

	function set_configuration_items(ci: configuration_items) return configurable_items is
		variable r: configurable_items;
	begin
		r.clocks         := ci(0).value;
		r.forever        := ci(1).value > 0;
		r.debug          := ci(2).value;
		r.interactive    := ci(3).value;
		r.input_wait_for := ci(4).value * 1 ms;
		r.report_uart    := ci(5).value > 0;
		r.report_number  := ci(6).value;
		r.input_single_line := ci(7).value > 0;
		r.uart_char_delay := ci(8).value * 1 ms;
		return r;
	end function;

	constant configuration_default: configuration_items(0 to 8) := (
		(name => "Clocks..", value => 1000),
		(name => "Forever.", value => 0),
		(name => "Debug...", value => 0), -- N.B. Doesn't work for setting generics, unfortunately 
		(name => "Interact", value => 0),
		(name => "InWaitMs", value => 15),
		(name => "UartRep.", value => 0),
		(name => "LogFor..", value => 256),
		(name => "1Line...", value => 1),
		(name => "UChDelay", value => 6)
	);

	-- Test bench configurable options --
	shared variable cfg: configurable_items := set_configuration_items(configuration_default);
	signal configured: boolean := false;
begin
	uart_tbs: if generate_uart_tbs generate
		uart_tb_0: entity work.uart_tb;
		uart_tb_1: entity work.uart_rx_tb;
	end generate;

	uut_g: if generate_non_io_tb generate
	uut: entity work.system
		generic map(
			g          => g,
			file_name  => program_file_name,
			N          => N,
			debug      => cfg.debug)
		port map (
			clk  => clk,
			rst  => rst,
			halted => halted,
			blocked => blocked,
			obyte => rx_data,
			ibyte => tx_data,
			obsy => obsy,
		       	ihav => ihav,
			io_we => rx_hav,
			io_re => io_re);
	end generate;

	uut_gn: if not generate_non_io_tb generate
	uut: entity work.top
		generic map(
			g          => g,
			file_name  => program_file_name,
			N          => N,
			baud       => baud,
			debug      => cfg.debug)
		port map (
			clk  => clk,
--			rst  => rst,
			halted => halted,
			blocked => blocked,
			tx   => rx,
			rx   => tx);

	uart_rx_0: entity work.uart_rx
		generic map(clks_per_bit => clks_per_bit)
		port map(
			clk          => clk,
			rx_serial    => rx,
			rx_have_data => rx_hav,
			rx_byte      => rx_data);
	end generate;

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
		while (count < cfg.clocks or cfg.forever) and halted = '0' loop
			clk <= '1';
			wait for clock_period / 2;
			clk <= '0';
			wait for clock_period / 2;
			count := count + 1;
		end loop;
		if halted = '1' then
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
		report "CPU Size:       " & positive'image(N);
		report "Baud:           " & positive'image(baud);
		report "Clocks Per Bit: " & integer'image(clks_per_bit);
		report "Bit Period:     " & time'image(bit_period);
		report "Program:        " & program_file_name;
		report "Config File:    " & configuration_file_name;

		read_configuration_tb(configuration_file_name, configuration_values);
		cfg := set_configuration_items(configuration_values);
		configured <= true;
		report "Configuration Complete";

		rst <= '1';
		wait for clock_period;
		rst <= '0';

		configured <= true;
		while not stop loop
			if rx_hav = '1' then saw_char <= true; end if;
			wait for clock_period;
		end loop;
		if saw_char then
			report "Saw character via UART";
		else
			report "No output from unit" severity warning;
		end if;
		report "Stimulus Process end";
		wait;
	end process;

	output_process: process
		variable oline: line;
		variable c: character;
		variable have_char: boolean := true;
	begin
		wait until configured;

		if cfg.interactive < 1 then
			report "Output process turned off (`interactive < 1`)";
			wait;
		end if;

		report "Writing to STDOUT";
		while not stop loop
			wait until rx_hav = '1' or stop;
			if not stop then
				c := character'val(to_integer(unsigned(rx_data)));
				if (cfg.report_uart) then
					report "BCPU -> UART CHAR: " & integer'image(to_integer(unsigned(rx_data))) & " CH: " & c;
				end if;
				write(oline, c);
				have_char := true;
				if rx_data = x"0d" then
					writeline(output, oline);
					have_char := false;
				end if;
				wait for clock_period;
			end if;
		end loop;
		if have_char then
			writeline(output, oline);
		end if;
		report "Output process end";
		wait;
	end process;

	-- The Input and Output mechanism that allows the tester to
	-- interact with the running simulation needs more work, it is buggy
	-- and experimental, but demonstrates the principle - that a VHDL
	-- test bench can be interacted with at run time.
	input_process: process
		variable c: character := ' ';
		variable iline: line;
		variable good: boolean := true;
		variable eoi:  boolean := false;

		procedure write_byte(
			ch: in character;
			signal read_enable: in std_ulogic;
			signal halt_system: in boolean;
			signal have_byte: out std_ulogic;
			signal byte_output: out std_ulogic_vector(7 downto 0)) is
		begin
			byte_output <= std_ulogic_vector(to_unsigned(character'pos(ch), byte_output'length));
			have_byte <= '1';
			wait for clock_period;
			wait until read_enable = '1' or halt_system;
			have_byte <= '0';
		end procedure;
	begin
		ihav <= '0';
		tx_data <= x"00";
		wait until configured;

		if cfg.interactive < 2 then
			report "Input process turned off (`interactive < 2`)";
			wait;
		end if;

		-- N.B. It would be better to read (optionally) from a file
		report "Waiting for " & time'image(cfg.input_wait_for) & " (before reading from STDIN)";
		wait for cfg.input_wait_for;
		report "Reading from STDIN (Hit EOF/CTRL-D/CTRL-Z After entering a line)";
		while stop = false and eoi = false loop
			if endfile(input) = true then exit; end if;
			report "INPUT-LINE> ";
			readline(input, iline);
			good := true;
			while good and not stop loop
				read(iline, c, good);
				if good then
					report "UART -> BCPU CHAR: " & integer'image(character'pos(c)) & " CH: " & c;
				else
					eoi := true;
					report "UART -> BCPU EOL/EOI: " & integer'image(character'pos(CR)) & " CR";
					if generate_non_io_tb then
						write_byte(CR, io_re, stop, ihav, tx_data);
					else
						uart_write_byte(baud, std_ulogic_vector(to_unsigned(character'pos(CR), tx_data'length)), tx);
					end if;
					wait for cfg.uart_char_delay;
					if stop then exit; end if;
					report "UART -> BCPU EOL/EOI: " & integer'image(character'pos(LF)) & " LF";
					c := LF;
				end if;
				if generate_non_io_tb then
					write_byte(c, io_re, stop, ihav, tx_data);
				else
					uart_write_byte(baud, std_ulogic_vector(to_unsigned(character'pos(c), tx_data'length)), tx);
				end if;
				wait for cfg.uart_char_delay;
			end loop;
			if cfg.input_single_line then exit; end if;
		end loop;
		report "Input process end";
		wait;
	end process;
end architecture;
