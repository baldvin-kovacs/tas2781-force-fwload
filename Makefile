# Manual install defaults to /usr/local + /etc (sysadmin locations).
# Distribution packages should override, e.g.:
#   make install DESTDIR="$pkgdir" PREFIX=/usr \
#        UNITDIR=/usr/lib/systemd/system \
#        UDEVRULEDIR=/usr/lib/udev/rules.d \
#        MODPROBEDIR=/usr/lib/modprobe.d

PREFIX      ?= /usr/local
BINDIR      ?= $(PREFIX)/bin
UNITDIR     ?= /etc/systemd/system
UDEVRULEDIR ?= /etc/udev/rules.d
MODPROBEDIR ?= /etc/modprobe.d

all: systemd/tas2781-force-fwload.service

systemd/tas2781-force-fwload.service: systemd/tas2781-force-fwload.service.in
	sed 's|@BINDIR@|$(BINDIR)|g' $< > $@

install: all
	install -Dm755 bin/tas2781-force-fwload $(DESTDIR)$(BINDIR)/tas2781-force-fwload
	install -Dm755 bin/tas2781-win-fw $(DESTDIR)$(BINDIR)/tas2781-win-fw
	install -Dm644 systemd/tas2781-force-fwload.service $(DESTDIR)$(UNITDIR)/tas2781-force-fwload.service
	install -Dm644 udev/90-tas2781-no-runtime-pm.rules $(DESTDIR)$(UDEVRULEDIR)/90-tas2781-no-runtime-pm.rules
	install -Dm644 modprobe.d/tas2781-force-fwload.conf $(DESTDIR)$(MODPROBEDIR)/tas2781-force-fwload.conf

uninstall:
	rm -f $(DESTDIR)$(BINDIR)/tas2781-force-fwload
	rm -f $(DESTDIR)$(BINDIR)/tas2781-win-fw
	rm -f $(DESTDIR)$(UNITDIR)/tas2781-force-fwload.service
	rm -f $(DESTDIR)$(UDEVRULEDIR)/90-tas2781-no-runtime-pm.rules
	rm -f $(DESTDIR)$(MODPROBEDIR)/tas2781-force-fwload.conf

clean:
	rm -f systemd/tas2781-force-fwload.service

.PHONY: all install uninstall clean
