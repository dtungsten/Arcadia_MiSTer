--------------------------------------------------------------------------------
-- Signetics 2637 UVI Universal Video Interface
--------------------------------------------------------------------------------
-- DO 10/2018
--------------------------------------------------------------------------------

--  00 .. CF  : RAM screen
--  D0 .. EF  : RAM user
--  F0        : /O1.VC
--  F1        :  O1.HC
--  F2        : /O2.VC
--  F3        :  O2.HC
--  F4        : /O3.VC
--  F5        :  O3.HC
--  F6        : /O4.VC
--  F7        :  O4.HC
--  F8        : ?
--  F9        : ?
--  FA        : ?
--  FB        : ?
--  FC        : V offset
--  FD        : Sound pitch / Color mode
--  FE        : Delay chars / random noise / sound ena / loudness
--  FF        : DMA row
-- 100 .. 17F : ?
-- 180 .. 187 : O1. font
-- 188 .. 18F : O2. font
-- 190 .. 197 : O3. font
-- 198 .. 19F : O4. font
-- 1A0 .. 1A7 : O5. font
-- 1A8 .. 1AF : O6. font
-- 1B0 .. 1B7 : O7. font
-- 1B8 .. 1BF : O8. font
-- 1C0 .. 1F7 : ?
-- 1F8        : Colour / refresh mode / graphic mode /
-- 1F9        : Colour characters / pot / charsize
-- 1FA        : Obj 3-4 colour
-- 1FB        : Obj 1-2 colour
-- 1FC        : Collision detect : chars
-- 1FD        : Collision detect : inter-objets
-- 1FE        : POT 2/4
-- 1FF        : POT 1/2

--       A         D
-- 0 : Text     
-- 1 :            Data
-- 2 : Charmap
-- 3 : Obj1map    Charsymbol
-- 4 : Obj2map    Charsymbol
-- 5 : Obj3map    Charsymbol
-- 6 : Obj4map    Charsymbol
-- 7 :            Charsymbol


-- 1800 .. 18FF : RAM

-- 1900 .. 197F : Buttons
-- 1980 .. 19FF : Regs
-- 1A00 .. 1AFF : RAM
-- 1B00 .. 1BFF : Mirror 1900 .. 19FF
--
-- 
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE std.textio.ALL;

LIBRARY work;
USE work.base_pack.ALL;

ENTITY sgs2637 IS
  PORT (
    ad   : IN  uv15;      -- Address bus
    
    dw   : IN  uv8;       -- Data write
    dr   : OUT uv8;       -- Data read
    
    req  : IN  std_logic;
    ack  : OUT std_logic;
    wr   : IN  std_logic;
    tick : IN  std_logic;
    
    vid_argb : OUT uv4;         -- I | R | G | B
    vid_de   : OUT std_logic;
    vid_hsyn : OUT std_logic;
    vid_vsyn : OUT std_logic;
    vid_ce   : OUT std_logic;
    vrst     : OUT std_logic;

    sound    : OUT uv8;

    pot1     : IN uv8;
    pot2     : IN uv8;
    pot3     : IN uv8;
    pot4     : IN uv8;

    np       : IN std_logic; -- 0=NTSC 60Hz, 1=PAL 50Hz
    
    reset    : IN std_logic;
    clk      : IN std_logic; -- 8x Pixel clock
    reset_na : IN std_logic;
    clear_ram : IN std_logic  -- clears video RAM when high (currently unused, logic disabled)
    );
END ENTITY sgs2637;

ARCHITECTURE rtl OF sgs2637 IS
  SUBTYPE uint9 IS natural RANGE 0 TO 511;
  -- uint10: wider horizontal position for object rendering with HOFFSET/hshift adjustment
  SUBTYPE uint10 IS natural RANGE 0 TO 1023;
  
  -- 64 chars * 8 lines  = 512
  CONSTANT CHARS : arr_uv8(0 TO 511) := (
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- ' '
      x"01",x"02",x"04",x"08",x"10",x"20",x"40",x"80",  -- /
      x"80",x"40",x"20",x"10",x"08",x"04",x"02",x"01",  -- \
      x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",x"FF",  -- #
      x"FF",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- "
      x"01",x"01",x"01",x"01",x"01",x"01",x"01",x"01",  -- |
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"FF",  -- _
      x"80",x"80",x"80",x"80",x"80",x"80",x"80",x"80",  -- |
      x"FF",x"01",x"01",x"01",x"01",x"01",x"01",x"01",  -- "|
      x"FF",x"80",x"80",x"80",x"80",x"80",x"80",x"80",  -- |"
      x"80",x"80",x"80",x"80",x"80",x"80",x"80",x"FF",  -- |_
      x"01",x"01",x"01",x"01",x"01",x"01",x"01",x"FF",  -- _|
      x"01",x"03",x"07",x"0F",x"1F",x"3F",x"7F",x"FF",  -- /
      x"80",x"C0",x"E0",x"F0",x"F8",x"FC",x"FE",x"FF",  -- \
      x"FF",x"FE",x"FC",x"F8",x"F0",x"E0",x"C0",x"80",  -- /
      x"FF",x"7F",x"3F",x"1F",x"0F",x"07",x"03",x"01",  -- \
      x"00",x"1C",x"22",x"26",x"2A",x"32",x"22",x"1C",  -- 0
      x"00",x"08",x"18",x"08",x"08",x"08",x"08",x"1C",  -- 1
      x"00",x"1C",x"22",x"02",x"0C",x"10",x"20",x"3E",  -- 2
      x"00",x"3E",x"02",x"04",x"0C",x"02",x"22",x"1C",  -- 3
      x"00",x"04",x"0C",x"14",x"24",x"3E",x"04",x"04",  -- 4
      x"00",x"3E",x"20",x"3C",x"02",x"02",x"22",x"1C",  -- 5
      x"00",x"0C",x"10",x"20",x"3C",x"22",x"22",x"1C",  -- 6
      x"00",x"7C",x"02",x"04",x"08",x"10",x"10",x"10",  -- 7
      x"00",x"1C",x"22",x"22",x"1C",x"22",x"22",x"1C",  -- 8
      x"00",x"1C",x"22",x"22",x"3E",x"02",x"04",x"18",  -- 9
      x"00",x"08",x"14",x"22",x"22",x"3E",x"22",x"22",  -- A
      x"00",x"3C",x"22",x"22",x"3C",x"22",x"22",x"3C",  -- B
      x"00",x"1C",x"22",x"20",x"20",x"20",x"22",x"1C",  -- C
      x"00",x"3C",x"22",x"22",x"22",x"22",x"22",x"3C",  -- D
      x"00",x"3E",x"20",x"20",x"3C",x"20",x"20",x"3E",  -- E
      x"00",x"3E",x"20",x"20",x"38",x"20",x"20",x"20",  -- F
      x"00",x"1E",x"20",x"20",x"20",x"26",x"22",x"1E",  -- G
      x"00",x"22",x"22",x"22",x"3E",x"22",x"22",x"22",  -- H
      x"00",x"1C",x"08",x"08",x"08",x"08",x"08",x"1C",  -- I
      x"00",x"02",x"02",x"02",x"02",x"02",x"22",x"1C",  -- J
      x"00",x"22",x"24",x"28",x"30",x"28",x"24",x"22",  -- K
      x"00",x"20",x"20",x"20",x"20",x"20",x"20",x"3E",  -- L
      x"00",x"22",x"36",x"2A",x"2A",x"22",x"22",x"22",  -- M
      x"00",x"22",x"22",x"32",x"2A",x"26",x"22",x"22",  -- N
      x"00",x"1C",x"22",x"22",x"22",x"22",x"22",x"1C",  -- O
      x"00",x"3C",x"22",x"22",x"3C",x"20",x"20",x"20",  -- P
      x"00",x"1C",x"22",x"22",x"22",x"2A",x"24",x"1A",  -- Q
      x"00",x"3C",x"22",x"22",x"3C",x"28",x"24",x"22",  -- R
      x"00",x"1C",x"22",x"20",x"1C",x"02",x"22",x"1C",  -- S
      x"00",x"3E",x"08",x"08",x"08",x"08",x"08",x"08",  -- T
      x"00",x"22",x"22",x"22",x"22",x"22",x"22",x"1C",  -- U
      x"00",x"22",x"22",x"22",x"22",x"22",x"14",x"08",  -- V
      x"00",x"22",x"22",x"22",x"2A",x"2A",x"36",x"22",  -- W
      x"00",x"22",x"22",x"14",x"08",x"14",x"22",x"22",  -- X
      x"00",x"22",x"22",x"14",x"08",x"08",x"08",x"08",  -- Y
      x"00",x"3E",x"02",x"04",x"08",x"10",x"20",x"3E",  -- Z
      x"00",x"00",x"00",x"00",x"00",x"00",x"0C",x"0C",  -- .
      x"00",x"00",x"00",x"00",x"00",x"08",x"08",x"10",  -- ,
      x"00",x"00",x"08",x"08",x"3E",x"08",x"08",x"00",  -- +
      x"00",x"08",x"1E",x"28",x"1C",x"0A",x"3C",x"08",  -- $
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- User char
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- User char
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- User char
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- User char
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- User char
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- User char
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",  -- User char
      x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00"); -- User char
  
  SIGNAL wreq : std_logic;
  SIGNAL ram : arr_uv8(0 TO 1023);
  -- RAM clear logic disabled: caused severe routing congestion
  -- SIGNAL ram_clear_idx : unsigned(10 DOWNTO 0) := to_unsigned(1024, 11);
  -- SIGNAL clear_ram_d : std_logic := '0';
  ATTRIBUTE ramstyle : string;
  ATTRIBUTE ramstyle OF ram : SIGNAL IS "no_rw_check";

  SIGNAL adi : uv12;
  SIGNAL ram_ad : uv10;  -- xxx_ad removed: unused, see commented block below
  SIGNAL ram_dr,rom_dr,ch : uv8;
  SIGNAL dr_reg,dr_mem : uv8;
  SIGNAL drreg_sel : std_logic;
  SIGNAL rom_ad : uv9;
  
  SIGNAL o1_hc,o1_vc,o2_hc,o2_vc : uv8; -- F0..F3
  SIGNAL o3_hc,o3_vc,o4_hc,o4_vc : uv8; -- F4..F7
  SIGNAL voffset : uv8;  -- FC
  SIGNAL r_0fd  : uv8; -- FD
  ALIAS  r_freq : uv7 IS r_0fd(6 DOWNTO 0); -- Sound Frequency
  ALIAS  r_cm   : std_logic IS r_0fd(7); -- Color mode
  
  SIGNAL r_0fe  : uv8; -- FE
  ALIAS hshift  : uv3 IS r_0fe(7 DOWNTO 5); -- Character shift
  ALIAS r_rng   : std_logic IS r_0fe(4); -- Random noise
  ALIAS r_sen   : std_logic IS r_0fe(3); -- Sound enable
  ALIAS r_loud  : uv3 IS r_0fe(2 DOWNTO 0); -- Sound loudness
  SIGNAL dmarow : uv4; -- FF -- DMA row
  SIGNAL r_1f8 : uv8;
  ALIAS r_gmode : std_logic IS r_1f8(7);     -- Graphic mode
  ALIAS r_ref : std_logic IS r_1f8(6);    -- Resolution vert.
  ALIAS r_acc : uv3 IS r_1f8(5 DOWNTO 3); -- Alternate Screen Colour
  ALIAS r_asc : uv3 IS r_1f8(2 DOWNTO 0); -- Alternate Screen Colour
  SIGNAL r_1f9 : uv8;
  ALIAS r_cc : uv3 IS r_1f9(5 DOWNTO 3); -- Character Colour
  ALIAS r_sc : uv3 IS r_1f9(2 DOWNTO 0); -- Screen Colour
  ALIAS r_pmux  : std_logic IS r_1f9(6); -- Pot mux
  ALIAS r_csize : std_logic IS r_1f9(7); -- Character Size
  SIGNAL r_1fa,r_1fb : uv8;
  ALIAS o1_size : std_logic IS r_1fb(7); -- Object 1 size
  ALIAS o2_size : std_logic IS r_1fb(6); -- Object 2 size
  ALIAS o3_size : std_logic IS r_1fa(7); -- Object 3 size
  ALIAS o4_size : std_logic IS r_1fa(6); -- Object 4 size
  ALIAS o1_col : uv3 IS r_1fb(5 DOWNTO 3); -- Object 1 colour
  ALIAS o2_col : uv3 IS r_1fb(2 DOWNTO 0); -- Object 2 colour
  ALIAS o3_col : uv3 IS r_1fa(5 DOWNTO 3); -- Object 3 colour
  ALIAS o4_col : uv3 IS r_1fa(2 DOWNTO 0); -- Object 4 colour
  SIGNAL ccoll : uv4; -- Character collision
  SIGNAL ocoll : uv6; -- Object collision
  SIGNAL ocoll_clr,ocoll_pre,ccoll_clr,ccoll_pre : std_logic;
  SIGNAL pot24, pot13 : uv8;

  SIGNAL o1_hit,o2_hit,o3_hit,o4_hit,bg_hit : std_logic;
  SIGNAL o12_coll,o13_coll,o23_coll,o14_coll,o34_coll,o24_coll : std_logic;
  SIGNAL o1c_coll,o2c_coll,o3c_coll,o4c_coll : std_logic;

  SIGNAL col_grb : uv3;
  -- Horizontal offset for text/object positioning (tuned for PAL/NTSC framing)
  CONSTANT HOFFSET : natural := 16;

  SIGNAL cyc : uint3;
  SIGNAL vrle,vrle_pre,hrle,hrle_pre,hpulse : std_logic;
  SIGNAL hpos,hlen,hsync,hdisp : uint9;
  SIGNAL vpos,vlen,vsync,vdisp : uint9;
  SIGNAL vpos_eff : uint9;
  -- NTSC vertical offset adjustment (0 = no adjustment, tune to match WinArcadia framing)
  CONSTANT NTSC_VOFFSET_ADJ : integer := 0;

  SIGNAL gmode : std_logic;
  
  ------------------------------------------------
  SIGNAL lfsr : uv32;
  SIGNAL stog : std_logic;
  SIGNAL snd_cpt : uv7;
  
  ------------------------------------------------
  -- Read object/character
  FUNCTION objadrs(
    vpos : uint9; -- Spot vertical   position
    vc   : uv8; -- Vertical   coordinate object
    size : std_logic; -- Object size
    no   : uint2) RETURN unsigned IS
    VARIABLE vpos_adj : integer := integer(vpos) - to_integer(vc);
  BEGIN
    IF vpos_adj < 0 THEN vpos_adj := 0; END IF;
    IF size='0' THEN -- 16 lines
      RETURN to_unsigned(384 + no*8 + ((vpos_adj/2) MOD 8), 10);
    ELSE -- 8 lines
      RETURN to_unsigned(384 + no*8 + (vpos_adj MOD 8), 10);
    END IF;
  END FUNCTION objadrs;

  ------------------------------------------------
  FUNCTION objbit(
    hpos : uint10; -- Spot horizontal position
    hc   : uv8 ) RETURN natural IS -- Horizontal coordinate object
    VARIABLE a : uint3;
    VARIABLE ihc : uint8 := to_integer(hc);
  BEGIN
    -- +256 ensures non-negative value for MOD 8 (VHDL negative MOD gives negative result)
    a:=(hpos + 256 - ihc) MOD 8;
    RETURN 7-a;
  END FUNCTION;
  
  ------------------------------------------------
  -- hpos is uint10 (not uint9) to handle adjusted values up to 552
  -- (hpos + 2*(HOFFSET+hshift) - 5 with hpos=511, hshift=7)
  FUNCTION objhit(
    hpos : uint10; -- Spot horizontal position
    vpos : uint9; -- Spot vertical   position
    hc   : uv8; -- Horizontal coordinate object
    vc   : uv8; -- Vertical   coordinate object
    size : std_logic) RETURN boolean IS -- Object size
    VARIABLE ivc : uint8 := to_integer(vc);
    VARIABLE ihc : uint8 := to_integer(hc);
  BEGIN
    
    IF hc > 227 THEN
      RETURN false;
    ELSIF size='1' THEN -- Small
      RETURN vpos>=ivc AND (vpos-ivc)<8 AND hpos>=ihc AND (hpos-ihc)<8;
    ELSE -- High
      RETURN vpos>=ivc AND (vpos-ivc)<16 AND hpos>=ihc AND (hpos-ihc)<8;
    END IF;
  END FUNCTION;

  ------------------------------------------------
  -- objhpos: adjusted horizontal position for object hit detection.
  -- Computes hpos + 2*(HOFFSET+hshift) - 5 in 10-bit unsigned arithmetic
  -- (avoids 32-bit integer arithmetic for routing efficiency).
  FUNCTION objhpos(
    hpos : uint9;
    hshift : uv3) RETURN uint10 IS
    VARIABLE result : unsigned(9 DOWNTO 0);
  BEGIN
    result := resize(to_unsigned(hpos, 10), 10) +
              to_unsigned(2*HOFFSET - 5, 10) +
              resize(hshift & '0', 10);
    RETURN to_integer(result);
  END FUNCTION;

  ------------------------------------------------
  -- objpix: object pixel index (0-7) for sprite rendering.
  -- Computes (hpos + 512 + 2*(HOFFSET+hshift) - 5 - hc) MOD 8 in 11-bit unsigned arithmetic.
  -- +512 ensures non-negative value for MOD 8 (VHDL negative MOD gives negative result).
  FUNCTION objpix(
    hpos : uint9;
    hshift : uv3;
    hc   : uv8) RETURN natural IS
    VARIABLE result : unsigned(10 DOWNTO 0);
  BEGIN
    result := resize(to_unsigned(hpos, 11), 11) +
              to_unsigned(512 + 2*HOFFSET - 5, 11) +
              resize(hshift & '0', 11) -
              resize(hc, 11);
    RETURN to_integer(result(2 DOWNTO 0));
  END FUNCTION;

  ------------------------------------------------
  FUNCTION pix(g : std_logic; -- 0=Text 1=Graph
               h : uint3;  -- Horizontal offset
               v : uint1;  -- Vertical   offset
               d : uv8;    -- Character font
               c : uv8) RETURN boolean IS -- Character code (for graphics)
  BEGIN
    IF g='0' THEN
      RETURN d(7-h)='1';
    ELSE
      IF    v=0 AND h<3 THEN  RETURN c(2)='1';
      ELSIF v=1 AND h<3 THEN  RETURN c(5)='1';
      ELSIF v=0 AND h<6 THEN  RETURN c(1)='1';
      ELSIF v=1 AND h<6 THEN  RETURN c(4)='1';
      ELSIF v=0         THEN  RETURN c(0)='1';
      ELSE                    RETURN c(3)='1';
      END IF;
    END IF;
  END FUNCTION;
  
  ------------------------------------------------

  SIGNAL xxx_bg : boolean;
  
BEGIN
  
  ack<='1';

  wreq<=wr AND req AND tick;
  adi <= ad(11 DOWNTO 0) - (ad(11) & "00000000000");

  dr<=dr_reg WHEN drreg_sel='1' ELSE dr_mem;
  
  Regs:PROCESS(clk,reset_na) IS
  BEGIN
    IF reset_na='0' THEN
      ocoll_pre<='0';
      ccoll_pre<='0';
      -- ram_clear_idx <= to_unsigned(1024, 11);
      -- clear_ram_d <= '0';
      
    ELSIF rising_edge(clk) THEN
      --------------------------------------------
      -- RAM clear on cart load (rising edge of clear_ram)
      -- DISABLED: caused severe routing congestion
      -- clear_ram_d <= clear_ram;
      -- IF clear_ram = '1' AND clear_ram_d = '0' AND ram_clear_idx >= 1024 THEN
      --   ram_clear_idx <= to_unsigned(0, 11);
      -- END IF;
      -- IF ram_clear_idx < 1024 THEN
      --   ram(to_integer(ram_clear_idx)) <= x"00";
      --   ram_clear_idx <= ram_clear_idx + 1;
      -- END IF;
      
      --------------------------------------------
      -- RAM
      dr_mem<=ram(to_integer(adi(9 DOWNTO 0)));

      IF wreq='1' THEN
        -- DEBUG: log 2637 register writes (F0-FF, 1F8-1FB) for debugging
        IF adi(9 DOWNTO 4)=x"0F" OR adi(9 DOWNTO 4)=x"1F" THEN
          REPORT "2637 reg write " & integer'image(to_integer(adi(9 DOWNTO 0))) &
                 " = " & integer'image(to_integer(dw)) SEVERITY NOTE;
        END IF;
        ram(to_integer(adi(9 DOWNTO 0)))<=dw;
      END IF;
      
      --------------------------------------------
      -- Registers
      drreg_sel<='0';
      dr_reg<=x"00";
      
      CASE adi IS
        WHEN x"0F0" =>  IF wreq='1' THEN o1_vc<=NOT dw; END IF;
        WHEN x"0F1" =>  IF wreq='1' THEN o1_hc<=dw; END IF;
        WHEN x"0F2" =>  IF wreq='1' THEN o2_vc<=NOT dw; END IF;
        WHEN x"0F3" =>  IF wreq='1' THEN o2_hc<=dw; END IF;
        WHEN x"0F4" =>  IF wreq='1' THEN o3_vc<=NOT dw; END IF;
        WHEN x"0F5" =>  IF wreq='1' THEN o3_hc<=dw; END IF;
        WHEN x"0F6" =>  IF wreq='1' THEN o4_vc<=NOT dw; END IF;
        WHEN x"0F7" =>  IF wreq='1' THEN o4_hc<=dw; END IF;
        WHEN x"0FC" =>  IF wreq='1' THEN voffset<=NOT dw - 1; END IF;
        WHEN x"0FD" =>  IF wreq='1' THEN r_0fd<=dw; END IF;
        WHEN x"0FE" =>  IF wreq='1' THEN r_0fe<=dw; END IF;
        WHEN x"0FF" =>  dr_reg<="1111" & dmarow; drreg_sel<='1';
        WHEN x"1F8" =>  IF wreq='1' THEN r_1f8<=dw; END IF;
        WHEN x"1F9" =>  IF wreq='1' THEN r_1f9<=dw; END IF;
        WHEN x"1FA" =>  IF wreq='1' THEN r_1fa<=dw; END IF;
        WHEN x"1FB" =>  IF wreq='1' THEN r_1fb<=dw; END IF;
        WHEN x"1FC" =>  dr_reg<="1111" & ccoll; drreg_sel<='1'; -- Coll bg
        WHEN x"1FD" =>  dr_reg<="11" & ocoll;   drreg_sel<='1'; -- Coll obj
        WHEN x"1FE" =>  dr_reg<=pot24; drreg_sel<='1'; -- POT24
        WHEN x"1FF" =>  dr_reg<=pot13; drreg_sel<='1'; -- POT13
        WHEN OTHERS =>  NULL;
      END CASE;

      --------------------------------------------
      -- Collisions
      IF (vrle_pre='1' AND vrle='0') OR ccoll_clr='1' THEN
        ccoll<="1111";
      ELSE
        ccoll<=ccoll AND NOT (o4c_coll & o3c_coll & o2c_coll & o1c_coll);
      END IF;
      
      IF adi=x"1FC" AND req='1' AND tick='1' THEN
        ccoll_pre<='1';
      END IF;
      
      ccoll_clr<='0';
      IF adi/=x"1FC" AND ccoll_pre='1' THEN
        ccoll_clr<='1';
        ccoll_pre<='0';
      END IF;
      
      IF (vrle_pre='1' AND vrle='0') OR ocoll_clr='1' THEN
        ocoll<="111111";
      ELSE
        ocoll<=ocoll AND NOT (o34_coll & o24_coll & o23_coll &
                              o14_coll & o13_coll & o12_coll);
      END IF;
      
      IF adi=x"1FD" AND req='1' AND tick='1' THEN
        ocoll_pre<='1';
      END IF;
      
      ocoll_clr<='0';
      IF adi/=x"1FD" AND ocoll_pre='1' THEN
        ocoll_clr<='1';
        ocoll_pre<='0';
      END IF;
      
      --------------------------------------------
      -- POT MUX
      pot13<=mux(r_pmux,pot3,pot1);
      pot24<=mux(r_pmux,pot4,pot2);
      
      --------------------------------------------
    END IF;
    
  END PROCESS Regs;

  ------------------------------------------------------------------------------
  -- Memory address mux
  -- NTSC vertical offset to match WinArcadia framing
  vpos_eff <= vpos - NTSC_VOFFSET_ADJ WHEN np='0' AND vpos >= NTSC_VOFFSET_ADJ ELSE
              0 WHEN np='0' ELSE
              vpos;

MadMux:PROCESS(ram_dr,vpos_eff,voffset,hpos,hshift,r_csize,
                 o1_size,o2_size,o3_size,o4_size,
                 o1_vc,o2_vc,o3_vc,o4_vc,cyc) IS
  BEGIN
    -- Character ROM
    IF r_csize='1' THEN
      rom_ad <= (ram_dr(5 DOWNTO 0) & "000") + ((vpos_eff + 256 - to_integer(voffset)) MOD 8);
    ELSE
      rom_ad <= (ram_dr(5 DOWNTO 0) & "000") + (((vpos_eff + 256 - to_integer(voffset)) / 2) MOD 8);
    END IF;
    
    -- xxx_ad: unused alternative text-mode address calculation.
    -- Kept for reference in case needed for debugging or PAL/NTSC switching work.
    -- IF (vpos) < 13*8  + to_integer(voffset) THEN
    --   xxx_ad <=to_unsigned(
    --     (hpos - HOFFSET - to_integer(hshift)) / 8
    --     + ((vpos - to_integer(voffset)) / 8) * 16,10);
    -- ELSE
    --   xxx_ad <=to_unsigned(512 +
    --      (hpos - HOFFSET - to_integer(hshift)) / 8
    --      + ((vpos - to_integer(voffset)) / 8 - 13) * 16,10);
    -- END IF;
    
    CASE cyc IS
      WHEN 1 | 7 | 0 => -- Read text image
        IF r_csize='1' THEN -- Small chars
          IF vpos_eff < 13*8 + to_integer(voffset) THEN
            ram_ad <=to_unsigned(
              ((hpos + 1024 - HOFFSET - to_integer(hshift)) MOD 1024) / 8
              + (((vpos_eff + 1024 - to_integer(voffset)) MOD 1024) / 8) * 16,10);
          ELSE
            ram_ad <=to_unsigned((512 +
              ((hpos + 1024 - HOFFSET - to_integer(hshift)) MOD 1024) / 8
              + ((((vpos_eff + 1024 - to_integer(voffset)) MOD 1024) / 8) - 13) * 16) MOD 1024,10);
          END IF;
          
        ELSE -- High chars
          ram_ad <=to_unsigned(
            ((hpos + 1024 - HOFFSET - to_integer(hshift)) MOD 1024) / 8
            + (((vpos_eff + 1024 - to_integer(voffset)) MOD 1024) / 16) * 16,10);
        END IF;
        
      WHEN 2 => -- Read user character shape
        IF r_csize='1' THEN
          ram_ad <= to_unsigned(384 + to_integer(ram_dr(2 DOWNTO 0)) * 8 +
                                 ((vpos_eff + 256 - to_integer(voffset)) MOD 8),10);
        ELSE
          ram_ad <= to_unsigned(384 + to_integer(ram_dr(2 DOWNTO 0)) * 8 +
                                 (((vpos_eff + 256 - to_integer(voffset)) / 2) MOD 8),10);
        END IF;
        
      WHEN 3 => -- Read object 1 shape
        ram_ad <=objadrs(vpos_eff,o1_vc,o1_size,0);
        
      WHEN 4 =>
        ram_ad <=objadrs(vpos_eff,o2_vc,o2_size,1);
        
      WHEN 5 =>
        ram_ad <=objadrs(vpos_eff,o3_vc,o3_size,2);
        
      WHEN 6 =>
        ram_ad <=objadrs(vpos_eff,o4_vc,o4_size,3);
        
    END CASE;
  END PROCESS MadMux;

  ------------------------------------------------------------------------------
  
  rom_dr<=CHARS(to_integer(rom_ad)) WHEN rising_edge (clk);
 
  Madar:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      ram_dr<=ram(to_integer(ram_ad));
    END IF;
  END PROCESS Madar;
  
  ------------------------------------------------------------------------------

  Vid:PROCESS (clk,reset_na) IS
    VARIABLE h,m : boolean;
    VARIABLE i : natural RANGE 0 TO 7;
    VARIABLE dm_v : uv8;
  BEGIN
    IF reset_na='0' THEN
      NULL;
    ELSIF rising_edge(clk) THEN
      --------------------------------------------
      -- PAL/NTSC video timing (np=0: NTSC, np=1: PAL)
      IF np='0' THEN
        -- NTSC
        hlen <=227;
        hsync<=224;
        hdisp<=160;
        vlen <=262;
        vsync<=228;
        vdisp<=226;
      ELSE
        -- PAL
        hlen <=227;
        hsync<=220;
        hdisp<=160;
        vlen <=312;
        vsync<=270;
        vdisp<=268;
      END IF;
      
      --------------------------------------------
      -- Collisions pulses
      o12_coll<='0';
      o23_coll<='0';
      o34_coll<='0';
      o13_coll<='0';
      o14_coll<='0';
      o24_coll<='0';
      o1c_coll<='0';
      o2c_coll<='0';
      o3c_coll<='0';
      o4c_coll<='0';
      
      hpulse<='0';

      --------------------------------------------
      cyc<=(cyc+1) MOD 8;
      
      CASE cyc IS
        WHEN 0 => -- Clear
          IF hpos<hlen THEN
            hpos<=hpos+1;
          ELSE
            hpos<=0;
            gmode<=r_gmode;
            IF vpos<vlen THEN
              vpos<=vpos+1;
            ELSE
              vpos<=0;
            END IF;
            
            hpulse<='1';
            
          END IF;

          o1_hit<='0';
          o2_hit<='0';
          o3_hit<='0';
          o4_hit<='0';
          bg_hit<='0';

          IF r_csize='1' THEN -- Small chars
            IF vpos_eff<to_integer(voffset) THEN
              dmarow<=to_unsigned(15,4);
            ELSIF vpos_eff<to_integer(voffset)+8*13 THEN
              dmarow<=to_unsigned((vpos_eff-to_integer(voffset))/8,4);
            ELSIF vpos_eff<to_integer(voffset)+8*13*2 AND r_ref='1' THEN
              dmarow<=to_unsigned((vpos_eff-to_integer(voffset))/8-13,4);
            ELSE
              dmarow<=to_unsigned(13,4);
            END IF;
          ELSE -- Tall chars
            IF vpos_eff<to_integer(voffset) THEN
              dmarow<=to_unsigned(15,4);
            ELSIF vpos_eff<to_integer(voffset)+16*13 THEN
              dmarow<=to_unsigned((vpos_eff-to_integer(voffset))/16,4);
            ELSE
              dmarow<=to_unsigned(13,4);
            END IF;
          END IF;

          o12_coll<=o1_hit AND o2_hit;
          o23_coll<=o2_hit AND o3_hit;
          o34_coll<=o3_hit AND o4_hit;
          o13_coll<=o1_hit AND o3_hit;
          o14_coll<=o1_hit AND o4_hit;
          o24_coll<=o2_hit AND o4_hit;
          o1c_coll<=o1_hit AND bg_hit;
          o2c_coll<=o2_hit AND bg_hit;
          o3c_coll<=o3_hit AND bg_hit;
          o4c_coll<=o4_hit AND bg_hit;

          vid_argb<='1' & NOT (col_grb(1) & col_grb(2) & col_grb(0));

        WHEN 1 =>
          -- Wait !
          NULL;
          
        WHEN 2 =>
          -- Character address
          ch<=ram_dr; -- Current character
          
        WHEN 3 =>
          -- Read Char. map : ROM + user char
          -- code charactère
          -- image ROM
          -- image user
          -- position écran
          -- paramètres : offset, hauteur, mode graphique
          IF ch(5 DOWNTO 0)<"111000" THEN
            dm_v:=rom_dr;
          ELSE
            dm_v:=ram_dr; -- User char.
          END IF;

          m:=true;

          IF r_csize='0' OR r_ref='1' THEN -- Full scree
            IF vpos_eff<to_integer(voffset) OR --to_integer(voffset)>=128 OR
              vpos_eff>=to_integer(voffset)+8*26 OR
              hpos<HOFFSET+to_integer(hshift) OR
              hpos>=16*8+HOFFSET+to_integer(hshift) THEN
              m:=false;
            END IF;

          ELSE -- Half, small chars
            IF vpos_eff<to_integer(voffset) OR --to_integer(voffset)>=128 OR
              vpos_eff>=to_integer(voffset)+8*13 OR
              hpos<HOFFSET+to_integer(hshift) OR
              hpos>=16*8+HOFFSET+to_integer(hshift) THEN
              m:=false;
            END IF;

          END IF;
          --IF r_csize='1' THEN -- 16x13 mode
          --  IF vpos<to_integer(voffset) OR to_integer(voffset)>=128 OR
          --    vpos>=to_integer(voffset)+16*13 OR
          --    hpos<HOFFSET+to_integer(hshift) OR
          --    hpos>=16*8+HOFFSET+to_integer(hshift) THEN
          --    m:=false;
          --  END IF;
          --ELSE -- 16x26 mode
          --  IF vpos<to_integer(voffset) OR to_integer(voffset)>=128 OR
          --    (vpos>=8*13+to_integer(voffset) AND r_ref='0') OR
          --    (vpos>=8*26+to_integer(voffset) AND r_ref='1') OR
          --    hpos<HOFFSET+to_integer(hshift) OR
          --    hpos>=16*8+HOFFSET+to_integer(hshift) THEN
          --    m:=false; 
          --  END IF;
          --END IF;
          
          xxx_bg<=m;
          
          IF ch=x"C0" AND m THEN -- Set GMODE special char
            gmode<='1';
            h:=false;
            
          ELSIF ch=x"40" AND m THEN -- Clear GMODE special char
            gmode<='0';
            h:=false;
            
          ELSIF m AND r_csize='1' THEN -- 16x13 mode
            h:=pix(gmode,(hpos + 256 - HOFFSET - to_integer(hshift)) MOD 8,
                   (((vpos_eff + 256 - to_integer(voffset)) / 4) MOD 2),dm_v,ch);
          ELSIF m THEN -- 16x26 mode
            h:=pix(gmode,(hpos + 256 - HOFFSET - to_integer(hshift)) MOD 8,
                   (((vpos_eff + 256 - to_integer(voffset)) / 8) MOD 2),dm_v,ch);
          ELSE
            h:=false;
          END IF;
          
          bg_hit<=to_std_logic(h AND m);
          
          IF r_cm='0' THEN -- Character Color Mode = 0
            col_grb<=mux(h AND m,ch(7 DOWNTO 6) & r_cc(0),r_sc);
          ELSE -- Character Color Mode = 1
            col_grb<=mux(h AND m,mux(ch(6),r_cc,r_acc),mux(ch(7),r_sc,r_asc));
          END IF;
          
        WHEN 4 => -- Object 1
          h:=objhit(objhpos(hpos,hshift),vpos_eff,o1_hc,o1_vc,o1_size);
          
          IF h THEN
            i:=7- objpix(hpos, hshift, o1_hc);
            IF ram_dr(i)='1' THEN
              o1_hit<='1';
              col_grb<=o1_col;
            END IF;
          END IF;
          
        WHEN 5 => -- Object 2
          h:=objhit(objhpos(hpos,hshift),vpos_eff,o2_hc,o2_vc,o2_size);
          
          IF h THEN
            i:=7- objpix(hpos, hshift, o2_hc);
            IF ram_dr(i)='1' THEN
              o2_hit<='1';
              col_grb<=o2_col;
            END IF;
          END IF;
          
        WHEN 6 => -- Object 3
          h:=objhit(objhpos(hpos,hshift),vpos_eff,o3_hc,o3_vc,o3_size);
          
          IF h THEN
            i:=7- objpix(hpos, hshift, o3_hc);
            IF ram_dr(i)='1' THEN
              o3_hit<='1';
              col_grb<=o3_col;
            END IF;
          END IF;
          
        WHEN 7 => -- Object 4
          h:=objhit(objhpos(hpos,hshift),vpos_eff,o4_hc,o4_vc,o4_size);
          
          IF h THEN
            i:=7- objpix(hpos, hshift, o4_hc);
            IF ram_dr(i)='1' THEN
              o4_hit<='1';
              col_grb<=o4_col;
            END IF;
          END IF;
          
      END CASE;
      
      vid_hsyn<=to_std_logic(hpos>hsync);
      vid_vsyn<=to_std_logic(vpos>vsync);
      vrle    <=to_std_logic(vpos>vsync);
      vrle_pre<=vrle;
      -- DEBUG: log vertical blanking transitions for PAL/NTSC timing debug
      IF vrle /= vrle_pre THEN
        REPORT "VRLE changed: vpos=" & integer'image(vpos) &
               " vsync=" & integer'image(vsync) &
               " vrle=" & std_logic'image(vrle) SEVERITY NOTE;
      END IF;
      hrle    <=to_std_logic(hpos>hsync);
      hrle_pre<=hrle;
      -- NTSC vertical offset adjustment for display enable
      IF np='0' THEN
        vid_de  <=to_std_logic(hpos<hdisp AND vpos>=NTSC_VOFFSET_ADJ AND vpos<vdisp);
      ELSE
        vid_de  <=to_std_logic(hpos<hdisp AND vpos<vdisp);
      END IF;
      
      vid_ce<=to_std_logic(cyc=0);
      
    --------------------------------------------
    END IF;


  END PROCESS Vid;

  vrst<=vrle;
  
  ------------------------------------------------------------------------------
  Sono:PROCESS(clk) IS
  BEGIN

    IF rising_edge(clk) THEN
      IF hpulse='1' THEN
        IF snd_cpt<r_freq THEN
          snd_cpt<=snd_cpt+1;
        ELSE
          snd_cpt<="0000000";
          stog<=NOT stog;
          lfsr<=lfsr(30 DOWNTO 0) &
                 (lfsr(31) XOR lfsr(30) XOR lfsr(29) XOR lfsr(9));
        END IF;
      END IF;
      
      IF r_freq=x"00" THEN
        stog<='0';
      END IF;  

      IF ((stog AND r_sen) XOR (lfsr(0) AND r_rng)) ='1' THEN
        sound<=r_loud & "00000";
      ELSE
        sound<= ("000"-r_loud) & "00000";
      END IF;

    END IF;
  END PROCESS Sono;
  
  
END ARCHITECTURE rtl;

