meh: meh.m
	 clang meh.m -framework Cocoa -o meh

app: meh
	sh appify.sh -s meh -n meh

clean:
	rm meh

install: app
	mv -f meh.app /Applications

default: app
all: default

.PHONY: meh app clean install default all
