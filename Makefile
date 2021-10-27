#
# Makefile
# luominghao, 2020-07-12 10:56
#

PREFIX = /usr/local/bin

AUTOSSH_RAW=autossh.sh
AUTOSSH_BIN=autossh

all:
	install -d -m 0755 $(PREFIX)/autossh.d
	install -m 0755 bin/$(AUTOSSH_RAW) $(PREFIX)/autossh.d
	ln -sf ./autossh.d/autossh.sh $(PREFIX)/$(AUTOSSH_BIN)

# vim:ft=make
#
