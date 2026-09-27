# Glass: bố cục cài đặt. PKGBUILD gọi các target install-* ở đây, nên
# đường dẫn cài chỉ được định nghĩa một chỗ.
#
#   make                                    build glassd, glassctl (cargo)
#   make check                              kiểm tra tĩnh + test (cần shellcheck, lua, luac,
#                                           desktop-file-validate, systemd-analyze, cargo,
#                                           dbus-run-session, python3)
#   make install DESTDIR=/tmp/root          cài thử vào thư mục tạm
#   sudo make install                       cài thẳng vào hệ thống (nên dùng PKGBUILD)

PREFIX        ?= /usr
BINDIR        ?= $(PREFIX)/bin
DATADIR       ?= $(PREFIX)/share
GLASSDIR      ?= $(DATADIR)/glass
SYSCONFDIR    ?= /etc
USERUNITDIR   ?= $(PREFIX)/lib/systemd/user
SESSIONDIR    ?= $(DATADIR)/wayland-sessions
SDDMCONFDIR   ?= $(PREFIX)/lib/sddm/sddm.conf.d
PORTALCONFDIR ?= $(SYSCONFDIR)/xdg/xdg-desktop-portal
DBUSSERVICEDIR ?= $(DATADIR)/dbus-1/services

CARGO            ?= cargo
CARGOFLAGS       ?= --locked
CARGO_TARGET_DIR ?= $(CURDIR)/daemon/target
export CARGO_TARGET_DIR

LUA  ?= lua
LUAC ?= luac

BIN          = glass-session glass-setup glass-doctor glass-screenshot
DAEMON_BIN   = glassd glassctl
UNITS        = glass-session.target glass-idle.service glass-wallpaper.service
DAEMON_UNITS = glassd.service glass-nightlight.service

# Thay @GLASS_DATADIR@, @BINDIR@ bằng đường dẫn cài thật.
SUBST = sed -e 's|@GLASS_DATADIR@|$(GLASSDIR)|g' -e 's|@BINDIR@|$(BINDIR)|g'

.PHONY: all build install install-session install-daemon install-sddm uninstall check \
        check-shell check-lua check-desktop check-units check-rust test wallpaper

all: build

# GLASS_DATADIR được nhúng vào glassd làm thư mục dữ liệu mặc định.
build:
	GLASS_DATADIR="$(GLASSDIR)" $(CARGO) build --release $(CARGOFLAGS) --manifest-path daemon/Cargo.toml

install: install-session install-daemon install-sddm

install-session:
	install -d "$(DESTDIR)$(BINDIR)"
	for f in $(BIN); do \
		$(SUBST) "bin/$$f" > "$(DESTDIR)$(BINDIR)/$$f"; \
		chmod 755 "$(DESTDIR)$(BINDIR)/$$f"; \
	done
	# Mặc định (gói quản lý) và bản mẫu cho ~/.config
	for f in $$(find defaults -type f); do \
		rel=$${f#defaults/}; \
		install -d "$(DESTDIR)$(GLASSDIR)/$$(dirname "$$rel")"; \
		$(SUBST) "$$f" > "$(DESTDIR)$(GLASSDIR)/$$rel"; \
	done
	for f in $$(find skel -type f); do \
		install -d "$(DESTDIR)$(GLASSDIR)/$$(dirname "$$f")"; \
		$(SUBST) "$$f" > "$(DESTDIR)$(GLASSDIR)/$$f"; \
	done
	install -Dm644 -t "$(DESTDIR)$(GLASSDIR)/palettes" theme/palettes/*.toml
	install -Dm644 -t "$(DESTDIR)$(GLASSDIR)/wallpapers" wallpapers/*.jpg
	# Tích hợp phiên
	install -Dm644 session/glass.desktop "$(DESTDIR)$(SESSIONDIR)/glass.desktop"
	for u in $(UNITS); do \
		install -Dm644 "session/systemd/$$u" "$(DESTDIR)$(USERUNITDIR)/$$u"; \
	done
	install -Dm644 session/portals/hyprland-portals.conf \
		"$(DESTDIR)$(PORTALCONFDIR)/hyprland-portals.conf"

# Không tự build: PKGBUILD build ở bước build() rồi mới cài.
install-daemon:
	for b in $(DAEMON_BIN); do \
		install -Dm755 "$(CARGO_TARGET_DIR)/release/$$b" "$(DESTDIR)$(BINDIR)/$$b"; \
	done
	install -Dm644 -t "$(DESTDIR)$(GLASSDIR)/templates" theme/runtime/*.j2
	for u in $(DAEMON_UNITS); do \
		install -d "$(DESTDIR)$(USERUNITDIR)"; \
		$(SUBST) "daemon/data/$$u" > "$(DESTDIR)$(USERUNITDIR)/$$u"; \
		chmod 644 "$(DESTDIR)$(USERUNITDIR)/$$u"; \
	done
	install -Dm644 daemon/data/io.github.canxphung.Glass1.service \
		"$(DESTDIR)$(DBUSSERVICEDIR)/io.github.canxphung.Glass1.service"

install-sddm:
	install -Dm644 session/sddm/glass.conf "$(DESTDIR)$(SDDMCONFDIR)/glass.conf"

uninstall:
	for f in $(BIN) $(DAEMON_BIN); do rm -f "$(DESTDIR)$(BINDIR)/$$f"; done
	rm -rf "$(DESTDIR)$(GLASSDIR)"
	rm -f "$(DESTDIR)$(SESSIONDIR)/glass.desktop"
	for u in $(UNITS) $(DAEMON_UNITS); do rm -f "$(DESTDIR)$(USERUNITDIR)/$$u"; done
	rm -f "$(DESTDIR)$(DBUSSERVICEDIR)/io.github.canxphung.Glass1.service"
	rm -f "$(DESTDIR)$(PORTALCONFDIR)/hyprland-portals.conf"
	rm -f "$(DESTDIR)$(SDDMCONFDIR)/glass.conf"

check: check-shell check-lua check-desktop check-units check-rust test

check-shell:
	LC_ALL=C.UTF-8 shellcheck -s sh bin/* tests/*.sh

check-lua:
	for f in $$(find defaults skel -name '*.lua'); do \
		$(LUAC) -p "$$f" || exit 1; \
	done

# File phiên không phải app thường: DesktopNames là khoá chuẩn của display
# manager (Hyprland cũng dùng) nhưng desktop-file-validate không biết.
check-desktop:
	@out=$$(desktop-file-validate session/glass.desktop 2>&1 | grep -v '"DesktopNames"' || true); \
	if [ -n "$$out" ]; then echo "$$out"; exit 1; fi; \
	echo "desktop: ok"

check-units:
	./tests/check-units.sh

check-rust:
	$(CARGO) fmt --all --manifest-path daemon/Cargo.toml --check
	$(CARGO) clippy $(CARGOFLAGS) --manifest-path daemon/Cargo.toml --all-targets -- -D warnings
	$(CARGO) test $(CARGOFLAGS) --manifest-path daemon/Cargo.toml

test:
	./tests/install-and-setup.sh
	LUA=$(LUA) ./tests/lua-smoke.sh
	./tests/glassd-smoke.sh

wallpaper:
	python3 wallpapers/make-aero.py
