# Source this: points the shell at the isolated test session, and refuses to
# continue if that session is not running (so nothing can reach the real one).
run=${XDG_RUNTIME_DIR:-/run/user/$(id -u)}
bus=$(cat "$run/nim-whisker-test.bus" 2>/dev/null)
disp=$(cat "$run/nim-whisker-test.display" 2>/dev/null)
case "$bus" in unix:path=/tmp/dbus-*) ;; *) echo "no isolated test session" >&2; return 1 2>/dev/null || exit 1;; esac
[ "$disp" != wayland-0 ] && [ -S "$run/$disp" ] || { echo "isolated session not running" >&2; return 1 2>/dev/null || exit 1; }
export DBUS_SESSION_BUS_ADDRESS="$bus" WAYLAND_DISPLAY="$disp" NO_AT_BRIDGE=1
export TESTDIR="$run/nim-whisker-test"
