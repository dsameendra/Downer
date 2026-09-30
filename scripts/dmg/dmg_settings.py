# dmgbuild settings for the Downer installer window.
# Run through scripts/make-dmg.sh, which passes app, icon and background with -D.
import os

app = defines["app"]            # path to Downer.app
icon = defines["icon"]          # Downer.icns, used for the mounted volume
background = defines["background"]

format = "UDBZ"
filesystem = "HFS+"
size = None                     # let dmgbuild size the image

files = [app]
symlinks = {"Applications": "/Applications"}
icon_locations = {
    os.path.basename(app): (170, 185),
    "Applications": (490, 185),
}

# the volume and the mounted disk show Downer's icon
badge_icon = None

# window: 660 × 420, icon view, no chrome. Everything important sits in the top 330 pt, so it stays
# visible even when the user has Finder's path bar and status bar turned on.
window_rect = ((200, 140), (660, 420))
default_view = "icon-view"
show_icon_preview = False
show_status_bar = False
show_tab_view = False
show_toolbar = False
show_pathbar = False
show_sidebar = False
icon_size = 128
text_size = 13
arrange_by = None
grid_offset = (0, 0)
grid_spacing = 100
scroll_position = (0, 0)
label_pos = "bottom"
include_icon_view_settings = "auto"
