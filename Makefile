# Glass: bố cục cài đặt. PKGBUILD gọi các target install-* ở đây, nên
# đường dẫn cài chỉ được định nghĩa một chỗ.
#
#   make check                              kiểm tra tĩnh + test (cần shellcheck, lua, luac,
#                                           desktop-file-validate, systemd-analyze)
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

LUA  ?= lua
LUAC ?= luac

BIN   = glass-session glass-setup glass-doctor glass-screenshot
UNITS = glass-session.target glass-idle.service glass-wallpaper.service

# Thay @GLASS_DATADIR@ bằng đường dẫn cài thật.
SUBST = sed -e 's|@GLASS_DATADIR@|$(GLASSDIR)|g'

.PHONY: all install install-session install-sddm uninstall check \
        check-shell check-lua check-desktop check-units test wallpaper

all:
	@echo "Không có gì để build ở giai đoạn 1. Xem: make check, make install."

install: install-session install-sddm

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

install-sddm:
	install -Dm644 session/sddm/glass.conf "$(DESTDIR)$(SDDMCONFDIR)/glass.conf"

uninstall:
	for f in $(BIN); do rm -f "$(DESTDIR)$(BINDIR)/$$f"; done
	rm -rf "$(DESTDIR)$(GLASSDIR)"
	rm -f "$(DESTDIR)$(SESSIONDIR)/glass.desktop"
	for u in $(UNITS); do rm -f "$(DESTDIR)$(USERUNITDIR)/$$u"; done
	rm -f "$(DESTDIR)$(PORTALCONFDIR)/hyprland-portals.conf"
	rm -f "$(DESTDIR)$(SDDMCONFDIR)/glass.conf"

check: check-shell check-lua check-desktop check-units test

check-shell:
	shellcheck -s sh bin/* tests/*.sh

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

test:
	./tests/install-and-setup.sh
	LUA=$(LUA) ./tests/lua-smoke.sh

wallpaper:
	python3 wallpapers/make-aero.py
