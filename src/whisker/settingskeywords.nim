## Extra search keywords for settings dialogs, so a query for what a dialog
## controls finds it ("wifi" -> Advanced Network Configuration). They add to
## the `Keywords` each `.desktop` file already declares. Entries for dialogs
## that are not installed are simply unused.

const extraKeywords = [
  ("xfce-display-settings.desktop",
    "monitor;scale;scaling;mirror;dual;second screen;orientation;arrange"),
  ("network.cycles.wdisplays.desktop",
    "monitor;screen;resolution;scale;scaling;arrange;rotation;refresh;wayland"),
  ("xfce-ui-settings.desktop",
    "theme;dark;light;dark mode;gtk;look;style;font;icon theme;scaling"),
  ("xfce-mouse-settings.desktop",
    "touchpad;trackpad;tap;tap to click;cursor;acceleration;natural " &
    "scrolling;left-handed;sensitivity"),
  ("xfce-keyboard-settings.desktop",
    "keybinding;hotkey;shortcut;repeat;delay;typing;language;input;cursor " &
    "blink"),
  ("xfce4-power-manager-settings.desktop",
    "energy;dim;blank;dpms;screen off;idle;lid;power saving;critical"),
  ("xfce4-notifyd-config.desktop",
    "notification;do not disturb;dnd;popup;banner;alerts;mute"),
  ("xfce-session-settings.desktop",
    "startup applications;boot;saved session;autostart;login"),
  ("xfce4-mime-settings.desktop",
    "default browser;default apps;preferred applications;mime;open with"),
  ("panel-preferences.desktop", "dock;bar;taskbar;plugins;items"),
  ("org.xfce.PanelProfiles.desktop", "dock;bar;layout"),
  ("xfce4-screensaver-preferences.desktop",
    "lock;idle;timeout;screen lock;blank"),
  ("xfce4-accessibility-settings.desktop",
    "mouse keys;slow keys;sticky keys;accessibility;universal access"),
  ("xfce4-settings-editor.desktop", "xfconf;advanced;tweak"),
  ("xfce-settings-manager.desktop", "preferences;options;configuration"),
  ("xfce-backdrop-settings.desktop",
    "wallpaper;background;desktop;desktop icons;image"),
  ("xfce-wm-settings.desktop",
    "window manager;title bar;focus;snap;window buttons;decorations"),
  ("xfce-wmtweaks-settings.desktop",
    "compositor;shadows;opacity;window switcher;alt tab"),
  ("xfce-workspaces-settings.desktop", "virtual desktops;workspace names"),
  ("xfce4-color-settings.desktop", "icc;calibration;color profile"),
  ("xfce4-clipman-settings.desktop", "clipboard;copy;paste;history"),
  ("thunar-volman-settings.desktop",
    "usb;automount;camera;removable;storage;drives;media"),
  ("org.pulseaudio.pavucontrol.desktop", "sound;mute;speaker;loudness"),
  ("nm-connection-editor.desktop",
    "wifi;wi-fi;wireless;ethernet;vpn;network;internet;ip;dns;proxy;" &
    "hotspot;connection"),
  ("blueman-manager.desktop", "bluetooth;pair;headset;wireless"),
  ("system-config-printer.desktop", "printer;printing;queue;cups"),
  ("cups.desktop", "printer;printing;queue"),
  ("org.bluesabre.Mugshot.desktop", "avatar;picture;name;account"),
  ("org.freedesktop.IBus.Setup.desktop", "input method;language;typing")]

func keywordsFor*(desktopId: string): string =
  ## Semicolon-separated extra keywords for a desktop ID; empty if none.
  for (id, keywords) in extraKeywords:
    if id == desktopId:
      return keywords
