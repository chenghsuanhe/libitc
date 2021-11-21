library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.itc.all;
use work.itc_lcd.all;


entity itc110_e1 is
	port (
		-- system
		clk, rst_n : in std_logic;
		-- lcd
		lcd_sclk, lcd_mosi, lcd_ss_n, lcd_dc, lcd_bl, lcd_rst_n : out std_logic;
		-- sw
		sw : in u8r_t;
		-- seg
		seg_led, seg_com : out u8r_t;
		-- key
		key_row : in u4r_t;
		key_col : out u4r_t;
		-- dht
		dht_data : inout std_logic;
		-- tts
		tts_scl, tts_sda : inout std_logic;
		tts_mo           : in unsigned(2 downto 0);
		tts_rst_n        : out std_logic
	);
end itc110_e1;

architecture arch of itc110_e1 is
	constant max_len : integer := 100;
	-- "?????????? 20
-- tts_data(0 to 19) <= sys ;
-- tts_len <= 20;
constant set_vol :u8_arr_t(0 to 1) :=(x"86", x"ff");
constant sys  : u8_arr_t(0 to 19) := (
	x"a8", x"74", x"b2", x"ce", x"b6", x"7d", x"be", x"f7", x"a9", x"f3", x"a6", x"7e", x"a4", x"eb", x"a4", x"e9",
	x"ac", x"50", x"b4", x"c1"
);

-- "??? 6
-- tts_data(0 to 5) <= time;
-- tts_len <= 6;
constant date : u8_arr_t(0 to 5) := (
	x"ae", x"c9", x"a4", x"c0", x"ac", x"ed"
);

-- "????, 6
-- tts_data(0 to 5) <= temp;
-- tts_len <= 6;
constant temp : u8_arr_t(0 to 5) := (
	x"b7", x"c5", x"ab", x"d7", x"ac", x"b0"
);

-- "6
-- tts_data(0 to 5) <= humd;
-- tts_len <= 6;
constant humd : u8_arr_t(0 to 5) := (
	x"c0", x"e3", x"ab", x"d7", x"ac", x"b0"
);

-- "??22
-- tts_data(0 to 21) <= num;
-- tts_len <= 22;

constant d_year : u8_arr_t(0 to 7) := (
        x"a4", x"47", x"b9", x"73", x"a4", x"47", x"a4", x"40"
);
	type mode_t is (none,idle, TFT_lcd_test, test2, start, setup,test_all);
	signal sub_mode : integer range 0 to 4;
	type lcd_t is (setup, lcd_scan);
	signal lcd : lcd_t;
	signal mode : mode_t;
	signal bg_color, text_color : l_px_t;
	signal ena, wr_ena : std_logic;
	signal addr : l_addr_t;
	signal load, msec : i32_t;
	signal seg_data : string(1 to 8);
	--key
	signal pressed, pressed_i : std_logic;
	signal key : i4_t;
	--seg 
	signal dot : u8_t;
	--lcd
	signal font_start : std_logic;
	signal font_busy : std_logic;
	signal draw_start, draw_done, lcd_clear : std_logic;
	signal x : integer range 0 to 127;
	signal y : integer range 0 to 158;
	signal data, data1, data2, data3 : string(1 to 12);
	signal lcd_count : integer range 0 to 9;
	signal set_tmp : integer range 0 to 40;
	signal set_hum : integer range 0 to 99;
	signal tmp : integer range 0 to 40 := 27;
	signal hum : integer range 0 to 99 := 75;
	signal hour : integer range 0 to 23 := 13;
	signal mins, secs : integer range 0 to 59 := 20;
	signal set_up_down : integer range -1 to 1;
	signal temp_int, hum_int : integer range 0 to 99;
	signal draw_color : integer range 0 to 7;
	signal clk_out, time_clk : std_logic;
	signal text_count : integer range 1 to 12;
	--tts
	signal tts_ena : std_logic;
	signal busy : std_logic;
	signal txt : u8_arr_t(0 to max_len - 1);
	signal len : integer range 0 to max_len;
	signal flag : integer range 0 to 3;
	signal status : integer range 0 to 10; 
	signal speak : integer range 0 to 10;
	signal done :boolean;
	signal year : integer range 2020 to 2023;
	signal days : integer range 1 to 31 :=13;
	signal month : integer range 1 to 12 :=12;
	signal presss_5 : std_logic;
	signal tts_start ,tts_done : std_logic;
	signal big_length : Integer range 0 to 99;
	signal latch ,dis,pause,resume: std_logic;
	signal tts_status : std_logic;
begin
	done <= (pressed='1') and (key = 0);

	tts_inst: entity work.tts(arch)
	generic map (
		txt_len_max => max_len
	)
	port map (
		clk => clk,
		rst_n => rst_n,
		tts_scl => tts_scl,
		tts_sda => tts_sda,
		tts_mo => tts_mo,
		tts_rst_n => tts_rst_n,
		ena => tts_ena,
		busy => busy,
		txt => txt,
		txt_len => len
	);
	edge_inst : entity work.edge(arch)
		port map(
			clk     => clk,
			rst_n   => rst_n,
			sig_in  => pressed_i,
			rising  => pressed,
			falling => open
		);
	dht_inst : entity work.dht(arch)
		port map(
			clk      => clk,
			rst_n    => rst_n,
			dht_data => dht_data,
			temp_int => temp_int,
			temp_dec => open,
			hum_int  => hum_int,
			hum_dec  => open
		);
	clk_inst : entity work.clk(arch)
		generic map(
			freq => 1
		)
		port map(
			clk_in  => clk,
			rst_n   => rst_n,
			clk_out => clk_out
		);
	edge_inst1 : entity work.edge(arch)
		port map(
			clk     => clk,
			rst_n   => rst_n,
			sig_in  => font_busy,
			rising  => draw_start,
			falling => draw_done
		);
	time_clk_edge_inst : entity work.edge(arch)
		port map(
			clk     => clk,
			rst_n   => rst_n,
			sig_in  => clk_out,
			rising  => time_clk,
			falling => open
		);
	key_inst : entity work.key(arch)
		port map(
			clk     => clk,
			rst_n   => rst_n,
			key_row => key_row,
			key_col => key_col,
			pressed => pressed_i,
			key     => key
		);
	lcd_draw : entity work.gen_font(arch)
		port map(
			clk        => clk,
			rst_n      => rst_n,
			x          => x,
			y          => y,
			font_start => font_start,
			font_busy  => font_busy,
			data       => data,
			text_count => text_count,
			text_color => text_color,
			bg_color   => bg_color,
			clear      => lcd_clear,
			lcd_sclk   => lcd_sclk,
			lcd_mosi   => lcd_mosi,
			lcd_ss_n   => lcd_ss_n,
			lcd_dc     => lcd_dc,
			lcd_bl     => lcd_bl,
			lcd_rst_n  => lcd_rst_n

		);
	seg_inst : entity work.seg(arch)
		port map(
			clk     => clk,
			rst_n   => rst_n,
			seg_led => seg_led,
			seg_com => seg_com,
			data    => seg_data,
			dot     => dot
		);
	timer_inst : entity work.timer(arch)
		port map(
			clk   => clk,
			rst_n => rst_n,
			ena   => ena,
			load  => 0,
			msec  => msec
		);
	edge3_inst: entity work.edge(arch)
	port map (
		clk => clk,
		rst_n => rst_n,
		sig_in => busy,
		rising => tts_start,
		falling => tts_done
	);
	edge4_inst: entity work.edge(arch)
	port map (
		clk => clk,
		rst_n => rst_n,
		sig_in => tts_status,
		rising => pause,
		falling =>resume
	);
	process (clk, rst_n)
	begin
		if rst_n = '0' then
			mode <= none;
			ena <= '0';
			tts_ena <= '0';
			sub_mode <= 1;
			dot <= x"00";
			seg_data <= "00000000";
			bg_color <= white;
			lcd_clear <= '1';
			font_start <= '0';
			x <= 0;
			y <= 0;
			tts_ena <= '0';
			set_tmp <= 27;
			set_hum <= 75;
			speak <= 1;
			latch <= '0';
			dis <= '0';
			status <= 0;
			sub_mode <= 0;
			tts_status <= '0' ;
			elsif rising_edge(clk) then
			if time_clk = '1'and tts_status = '0'then
				if secs = secs'high then
					secs <= 0;
					if mins = mins'high then
						mins <= 0;
						if hour = hour'high then
							hour <= 0;
						else
							hour <= hour + 1;
						end if;
					else
						mins <= mins + 1;
					end if;
				else
					secs <= secs + 1;
				end if;
			end if;
			if sw(6 to 7) ="00" and done then
				mode <= TFT_lcd_test;
				bg_color <= white;
				dis <= '0';
				ena <= '0';
				lcd_clear <= '0';
			end if;
			if sw(6 to 7) ="01"and done  then 
				mode <= start;
				dis <= '0';
				sub_mode <= 0;
				lcd_clear <= '0';
			end if;
			if sw(6 to 7) ="10" and done  then 
				dis <= '1';
				bg_color <= white;
				lcd_count <= 0;
				lcd_clear <= '0';
				font_start <= '0';
			end if;
			if sw(6 to 7) ="11" and done  then 
				mode <= test_all;
				lcd_count <= 0;
				font_start <= '0';
				bg_color <= white;
				dis <= '1';
				if latch = '0' then
					latch <= '1';
				else
					tts_status <= not tts_status;
				end if;
				tts_ena <= '0';
				lcd_clear <= '0';
			end if;
			case mode is
				when none => 
					null;
				when idle =>
					if bg_color = black then
						bg_color <= white;
						lcd_clear <= '1';
					end if;
					if bg_color = white and draw_done = '1' then
						font_start <= '0';
						lcd_clear <= '0';
						mode <= test2;
					end if;
				when TFT_lcd_test =>
					ena <= '1';
					lcd_clear <= '0';
					if msec >= 500 and bg_color = white then
						if font_busy = '0' then
							bg_color <= black;
							lcd_clear <= '1';
						end if;
					elsif bg_color = black and msec >= 1000 then
						ena <= '0';
						font_start <= '0';
						lcd_clear <= '0';
						text_color <= x"0000ff";
						lcd_count <= 1;
						mode <= idle;
						y <= 0;
					end if;

				when test2 =>
					case lcd_count is
						when 1 =>
							if ena = '0' then
								ena <= '1';
							end if;
							if font_busy = '0' then
								font_start <= '1';
							end if;
							if y = 0 then
								data <= "Mon.        ";
								if draw_done = '1' then
									y <= 20;
									font_start <= '0';
								end if;
							end if;
							if y = 20 then
								data <= " 1          ";
								if msec >= 1500 then
									lcd_count <= 2;
									font_start <= '0';
									y <= 20;
								end if;
							end if;
						when 2 =>
							if font_busy = '0' then
								font_start <= '1';
							end if;
							if y = 20 then
								data <= " 1  2       ";
								if draw_done = '1' then
									y <= 40;
									font_start <= '0';
								end if;
							end if;
							if y = 40 then
								data <= "   Tue.     ";
								if msec >= 2000 then
									lcd_count <= 3;
									font_start <= '0';
									y <= 20;
								end if;
							end if;
						when 3 =>
							if font_busy = '0' then
								font_start <= '1';
							end if;
							if y = 20 then
								data <= " 1  2  3    ";
								if draw_done = '1' then
									y <= 0;
									font_start <= '0';
								end if;
							end if;
							if y = 0 then
								data <= "Mon.  Wed.  ";
								if msec >= 2500 then
									lcd_count <= 4;
									font_start <= '0';
									y <= 20;
								end if;
							end if;

						when 4 =>
							if font_busy = '0' then
								font_start <= '1';
							end if;
							if y = 20 then
								data <= " 1  2  3 4  ";
								if draw_done = '1' then
									y <= 40;
									font_start <= '0';
								end if;
							end if;
							if y = 40 then
								data <= "   Tue. Thu.";
								if msec >= 3000 then
									lcd_count <= 5;
									font_start <= '0';
									y <= 60;
								end if;
							end if;
						when 5 => ---second line
							if font_busy = '0' then
								font_start <= '1';
							end if;
							if y = 60 then
								data <= "Fri.        ";
								if draw_done = '1' then
									y <= 80;
									font_start <= '0';
								end if;
							end if;
							if y = 80 then
								data <= " 5          ";
								if msec >= 3500 then
									lcd_count <= 6;
									font_start <= '0';
									y <= 100;
								end if;
							end if;
						when 6 =>
							if font_busy = '0' then
								font_start <= '1';
							end if;
							if y = 100 then
								data <= "   Sat.     ";
								if draw_done = '1' then
									y <= 80;
									font_start <= '0';
								end if;
							end if;
							if y = 80 then
								data <= " 5  6       ";
								if msec >= 4000 then
									lcd_count <= 7;
									font_start <= '0';
									y <= 80;
								end if;
							end if;
						when 7 =>
							if font_busy = '0' then
								font_start <= '1';
							end if;
							if y = 80 then
								data <= " 5  6  7    ";
								if draw_done = '1' then
									y <= 60;
									font_start <= '0';
								end if;
							end if;
							if y = 60 then
								data <= "Fri.  Sun.  ";
								if msec >= 4500 then
									lcd_count <= 8;
									font_start <= '0';
									y <= 80;
								end if;
							end if;
						when 8 =>
							if font_busy = '0' then
								font_start <= '1';
							end if;
							if y = 80 then
								data <= " 5  6  7  8 ";
								if draw_done = '1' then
									y <= 100;
									font_start <= '0';
								end if;
							end if;
							if y = 100 then
								data <= "   Sat.  dC ";
								if msec >= 5000 then
									lcd_count <= 9;
									font_start <= '0';
									y <= 120;
								end if;
							end if;
						when 9 =>
							if font_busy = '0' then
								font_start <= '1';
							end if;
							if y = 120 then
								data <= " :          ";
								if draw_done = '1' then
									y <= 140;
									font_start <= '0';
								end if;
							end if;
							if y = 140 then
								data <= " 9          ";
								if msec >= 5500 then
									y <= 120;
									mode <= none;
									lcd_clear <= '0';
									lcd_count <= 0;
									font_start <= '0';
									ena <= '0';
								end if;
							end if;
						when others =>
					end case;
				when start =>
						dot <= b"00000100";
						if dis = '0' then
							if draw_done = '1'  then
								bg_color <= red;
								lcd_clear <= '0';
							else 
								lcd_clear <= '1';
							end if;
						end if;
						if pressed = '1' then

							case key is
								when 4 =>
									if sub_mode < 4 then
										sub_mode <= sub_mode + 1;
									else
										sub_mode <= 4;
									end if;
								when 5 =>
									if sub_mode > 0 then
										sub_mode <= sub_mode - 1;
									else
										sub_mode <= 0;
									end if;
								when 3 =>
									mode <= setup;
								when 6 => 
									status <= sub_mode + 1;
									mode <= test_all;
								when others =>
									null; 
							end case;
						end if;

							case sub_mode is
								when 0 =>
									seg_data <= "ModE0000";
								when 1 =>
									seg_data <= "ModE0100";
								when 2 =>
									seg_data <= "ModE02" & to_string(set_tmp, set_tmp'high, 10, 2);
								when 3 =>
									seg_data <= "ModE03" & to_string(set_hum, set_hum'high, 10, 2);
								when others => null;
							end case;
				when setup =>
					if pressed = '1' then
						case key is
							when 4 =>
								if sub_mode = 2 then
									set_tmp <= set_tmp + 1;
								elsif sub_mode = 3 then
									set_hum <= set_hum + 1;

								end if;
							when 5 =>
								if sub_mode = 2 then
									set_tmp <= set_tmp - 1;
								elsif sub_mode = 3 then
									set_hum <= set_hum - 1;

								end if;
							when 6 =>
								mode <= test_all;
								tmp <= set_tmp;
								hum <= set_hum;
							when others =>
						end case;
					end if;
						case sub_mode is
							when 0 =>
								seg_data <= "ModE0000";
							when 1 =>
								seg_data <= "ModE0100";
							when 2 =>
								seg_data <= "ModE02" & to_string(set_tmp, set_tmp'high, 10, 2);
							when 3 =>
								seg_data <= "ModE03" & to_string(set_hum, set_hum'high, 10, 2);
							when others => null;
						end case;
				when test_all => 
					if pressed = '1' then
						case key is
							when 0 => 
							when 1 => 
							when 2 => 
								mode <= start;
							when 3 => 
								mode <= setup;
							when 4 =>

							when 5 => 
							when 6 =>

							when others => 
								null; 
						end case;
					end if;
					case status is
						when 0 =>  
							bg_color <= white;
							lcd_clear <= '1';
							if draw_done = '1' then
								lcd_clear <= '0';
								status <= 1;
							end if;
						when 1 =>
							seg_data <= "ModE0000" ;
							if latch = '0' then
								tts_ena <= '1';
								latch <= '1';
							end if;
							txt(0 to 47) <= tts_set_vol & x"ff" & sys(0 to 9) &
							                d_year & sys(10 to 11) &
											to_big(month) & sys(12 to 13) &
											to_big(days) & sys(14 to 15) &
											sys(16 to 19) & to_big(2);
							len <= 48;
							sub_mode <= 0;
							if tts_start = '1' then
								tts_ena <= '0';
							end if;
						when 2 => 
							seg_data <= "ModE0100" ;	
							sub_mode <= 1;
						when 3 => 
							sub_mode <= 2;
							speak <= 3;
							seg_data <= "ModE02" & to_string(tmp, tmp'high, 10, 2);
						when 4 => 
							sub_mode <= 3;
							speak <= 4;
							seg_data <= "ModE03" & to_string(hum, hum'high, 10, 2);
						when others => 
							null;
					end case;
				when others =>
					null;
			end case;
			if pause = '1' then 
				txt(0 to 1) <= tts_instant_pause;
				len <= 2;
				tts_ena <= '1';
			elsif resume = '1' then
				txt(0 to 1) <= tts_instant_resume;
				len <= 2;
				tts_ena <= '1';	
			else
			case  speak is 
			when 2 => 
				txt(0 to 25) <=set_vol & to_big(hour)&date(0 to 1) & to_big(mins)&date(2 to 3) & to_big(secs)&date(4 to 5);
				len <= 26;
				tts_ena <= '1';
				if tts_done= '1' then
					tts_ena <= '0';
				end if;
			when 3 => 
				txt(0 to 11) <=temp(0 to 5) & to_big(temp_int);
				len <= 12;
				tts_ena <= '1';
				if tts_done= '1' then
					tts_ena <= '0';
				end if;
				
			when 4 => 
				txt(0 to 11) <=humd(0 to 5) & to_big(hum_int);
				len <= 12;
				tts_ena <= '1';
				if tts_done= '1' then
					tts_ena <= '0';
				end if;
			when others => 
				null;			
			end case;		
			end if;
			if dis = '1' and tts_status = '0' then
				case lcd_count is
					when 0 =>
						bg_color <= white;
						if font_busy = '0' then
							lcd_clear <= '1';
						else
							lcd_clear <= '0';
						end if;
						if draw_done = '1' and lcd_clear <= '1' then
							lcd_clear <= '0';
							lcd_count <= 1;
						end if;
					when 1 =>
						data <= "20210615Tue.";
						y <= 0;
						x <= 0;
						if font_busy = '0' then
							font_start <= '1';
						else
							font_start <= '1';
						end if;
						if draw_done = '1' then
							lcd_count <= 2;
							font_start <= '0';
						end if;
					when 2 =>
						y <= 40;
						x <= 0;
						data <= "  " & to_string(hour, hour'high, 10, 2) & ":" & to_string(mins, mins'high, 10, 2) & ":" & to_string(secs, secs'high, 10, 2) & "  ";
						font_start <= '1';
						if draw_done = '1' then
							lcd_count <= 3;
							font_start <= '0';
						end if;
					when 3 =>
						y <= 100;
						x <= 0;
						data <= "  " & to_string(temp_int, temp_int'high, 10, 2) & "dC " & to_string(hum_int, hum_int'high, 10, 2) & '%' & "  ";
						font_start <= '1';
						if text_count = 8 and hum_int >= hum then
							text_color <= red;
						end if;
						if text_count = 1 and temp_int >= tmp then
							text_color <= red;
						end if;
						if text_count = 7 and text_color = red then
							text_color <= blue;
						end if;
						if draw_done = '1' then
							lcd_count <= 1;
							text_color <= blue;
							font_start <= '0';
						end if;
					when others =>
						null;
				end case;
			end if;
		end if;
	end process;
end arch;
