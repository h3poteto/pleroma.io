@meta {
  name: Breezy DX;
  author: HJ;
  license: WTFPL;
  website: ebin.club;
}

@palette.Dark {
  bg: #292C32;
  fg: #292C32;
  text: #ffffff;
  link: #1CA4F3;
  accent: #1CA4F3;
  cRed: #f41a51;
  cBlue: #1CA4F3;
  cGreen: #1af46e;
  cOrange: #f4af1a;
}

@palette.Light {
  bg: #EFF0F2;
  fg: #EFF0F2;
  text: #1B1F22;
  underlay: #5d6086;
  accent: #1CA4F3;
  cBlue: #1CA4F3;
  cRed: #f41a51;
  cGreen: #0b6a30;
  cOrange: #f4af1a;
  border: #d8e6f9;
  link: #1CA4F3;
}

@palette.Panda {
  bg: #EFF0F2;
  fg: #292C32;
  text: #1B1F22;
  link: #1CA4F3;
  accent: #1CA4F3;
  cRed: #f41a51;
  cBlue: #1CA4F3;
  cGreen: #0b6a30;
  cOrange: #f4af1a;
}

Root {
  --badgeNotification: color | --cRed;
  --buttonDefaultHoverGlow: shadow | inset 0 0 0 1 --accent / 1;
  --buttonDefaultFocusGlow: shadow | inset 0 0 0 1 --accent / 1;
  --buttonDefaultShadow: shadow | inset 0 0 0 1 --text / 0.35, 0 5 5 -5 #000000 / 0.35;
  --buttonDefaultBevel: shadow | inset 0 14 14 -14 #FFFFFF / 0.1;
  --buttonPressedBevel: shadow | inset 0 -20 20 -20 #000000 / 0.05;
  --defaultInputBevel: shadow | inset 0 0 0 1 --text / 0.35;
  --defaultInputHoverGlow: shadow | 0 0 0 1 --accent / 1;
  --defaultInputFocusGlow: shadow | 0 0 0 1 --link / 1;
}

Button {
  background: --parent;
}

Button:disabled {
  shadow: --buttonDefaultBevel, --buttonDefaultShadow
}

Button:hover {
  background: --inheritedBackground;
  shadow: --buttonDefaultHoverGlow, --buttonDefaultBevel, --buttonDefaultShadow
}

Button:toggled {
  background: $blend(--inheritedBackground 0.3 --accent)
}

Button:pressed {
  background: $blend(--inheritedBackground 0.8 --accent)
}

Button:pressed:toggled {
  background: $blend(--inheritedBackground 0.2 --accent)
}

Button:toggled:hover {
  background: $blend(--inheritedBackground 0.3 --accent)
}

Input {
  shadow: --defaultInputBevel;
  background: $mod(--bg -10);
}

PanelHeader {
  shadow: inset 0 30 30 -30 #ffffff / 0.25
}

Tab:hover {
  shadow: --buttonDefaultHoverGlow, --buttonDefaultBevel, --buttonDefaultShadow
}

Tab {
  background: --bg;
}
