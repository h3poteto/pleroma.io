@meta {
  name: Redmond DX;
  author: HJ;
  license: WTFPL;
  website: ebin.club;
}

@palette.Modern {
  bg: #D3CFC7;
  fg: #092369;
  text: #000000;
  link: #0000FF;
  accent: #A5C9F0;
  cRed: #FF3000;
  cBlue: #009EFF;
  cGreen: #309E00;
  cOrange: #FFCE00;
}

@palette.Classic {
  bg: #BFBFBF;
  fg: #000180;
  text: #000000;
  link: #0000FF;
  accent: #A5C9F0;
  cRed: #FF0000;
  cBlue: #2E2ECE;
  cGreen: #007E00;
  cOrange: #CE8F5F;
}

@palette.Vapor {
  bg: #F0ADCD;
  fg: #bca4ee;
  text: #602040;
  link: #064745;
  accent: #9DF7C8;
  cRed: #86004a;
  cBlue: #0e5663;
  cGreen: #0a8b51;
  cOrange: #787424;
}

Root {
  --gradientColor: color | --accent;
  --inputColor: color | #FFFFFF;
  --bevelLight: color | $brightness(--bg 50);
  --bevelDark: color | $brightness(--bg -20);
  --bevelExtraDark: color | #404040;
  --buttonDefaultBevel: shadow | $borderSide(--bevelExtraDark bottom-right 1 1), $borderSide(--bevelLight top-left 1 1), $borderSide(--bevelDark bottom-right 1 2);
  --buttonPressedFocusedBevel: shadow | inset 0 0 0 1 #000000 / 1 #Outer , inset 0 0 0 2 --bevelExtraDark / 1 #inner;
  --buttonPressedBevel: shadow | $borderSide(--bevelDark top-left 1 1), $borderSide(--bevelLight bottom-right 1 1), $borderSide(--bevelExtraDark top-left 1 2);
  --defaultInputBevel: shadow | $borderSide(--bevelDark top-left 1 1), $borderSide(--bevelLight bottom-right 1 1), $borderSide(--bevelExtraDark top-left 1 2), $borderSide(--bg bottom-right 1 2);
}

Button:toggled {
  background: --bg;
  shadow: --buttonPressedBevel
}

Button:focused {
  shadow: --buttonDefaultBevel, 0 0 0 1 #000000 / 1
}

Button:pressed {
  shadow: --buttonPressedBevel
}

Button:hover {
  shadow: --buttonDefaultBevel;
  background: --bg
}

Button {
  shadow: --buttonDefaultBevel;
  background: --bg;
  roundness: 0
}

Button:pressed:hover {
  shadow: --buttonPressedBevel
}

Button:hover:pressed:focused {
  shadow: --buttonPressedFocusedBevel
}

Button:pressed:focused {
  shadow: --buttonPressedFocusedBevel
}

Button:toggled:pressed {
  shadow: --buttonPressedFocusedBevel
}

Input {
  background: $boost(--bg 20);
  shadow: --defaultInputBevel;
  roundness: 0
}

Input:focused {
  shadow: inset 0 0 0 1 #000000 / 1, --defaultInputBevel
}

Input:focused:hover {
  shadow: --defaultInputBevel
}

Input:focused:hover:disabled {
  shadow: --defaultInputBevel
}

Input:hover {
  shadow: --defaultInputBevel
}

Input:disabled {
  shadow: --defaultInputBevel
}

Panel {
  shadow: --buttonDefaultBevel;
  roundness: 0
}

PanelHeader {
  shadow: inset -1100 0 1000 -1000 --gradientColor / 1 #Gradient ;
  background: --fg
}

PanelHeader ButtonUnstyled Icon {
  textColor: --text;
  textAuto: 'no-preserve'
}

PanelHeader Button Icon {
  textColor: --text;
  textAuto: 'no-preserve'
}

PanelHeader Button Text {
  textColor: --text;
  textAuto: 'no-preserve'
}

Tab:hover {
  background: --bg;
  shadow: --buttonDefaultBevel
}

Tab:active {
  background: --bg
}

Tab:active:hover {
  background: --bg;
  shadow: --defaultButtonBevel
}

Tab:active:hover:disabled {
  background: --bg
}

Tab:hover:disabled {
  background: --bg
}

Tab:disabled {
  background: --bg
}

Tab {
  background: --bg;
  shadow: --buttonDefaultBevel
}

Tab:hover:active {
  shadow: --buttonDefaultBevel
}

TopBar Link {
  textColor: #ffffff
}

MenuItem:hover {
  background: --fg
}

MenuItem:active {
  background: --fg
}

MenuItem:active:hover {
  background: --fg
}

Popover {
  shadow: --buttonDefaultBevel, 5 5 0 0 #000000 / 0.2;
  roundness: 0
}
