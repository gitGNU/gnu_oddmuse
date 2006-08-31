# The Makefile is only for developpers wanting to prepare the tarball.
# Make sure the CVS keywords for the sed command on the next line are not expanded.

VERSION=oddmuse-$(shell sed -n -e 's/^.*\$$Id: wiki\.pl,v \([0-9.]*\).*$$/\1/p' wiki.pl)
UPLOADVERSION=oddmuse-inkscape-$(shell sed -n -e 's/^.*\$$Id: wikiupload,v \([0-9.]*\).*$$/\1/p' wikiupload)
TRANSLATIONS=$(wildcard modules/translations/[a-z]*-utf8.pl$)
MODULES=$(wildcard modules/*.pl)
INKSCAPE=GPL $(wildcard inkscape/*.py inkscape/*.inx inkscape/*.sh)

dist: $(VERSION).tar.gz

upload: $(VERSION).tar.gz $(VERSION).tar.gz.sig \
	$(UPLOADVERSION).tar.gz $(UPLOADVERSION).tar.gz.sig
	for f in $^; do \
		curl -T $$f ftp://savannah.gnu.org/incoming/savannah/oddmuse/; \
	done

upload-text: new-utf8.pl
	wikiupload new-utf8.pl http://www.oddmuse.org/cgi-bin/oddmuse-en/New_Translation_File

$(VERSION).tar.gz:
	rm -rf $(VERSION)
	mkdir $(VERSION)
	cp README FDL GPL ChangeLog wiki.pl $(TRANSLATIONS) $(MODULES) $(VERSION)
	tar czf $(VERSION).tar.gz $(VERSION)

$(UPLOADVERSION).tar.gz: $(INKSCAPE)
	rm -rf $(UPLOADVERSION)
	mkdir $(UPLOADVERSION)
	cp $^ $(UPLOADVERSION)
	cp wikiupload $(UPLOADVERSION)/oddmuse-upload.py
	tar czf $(UPLOADVERSION).tar.gz $(UPLOADVERSION)

%.tar.gz.sig: %.tar.gz
	gpg --sign -b $<

# 1. update-translations (will fetch input from the wiki, and updates files)
# 2. check changes, cvs commit
# 3. upload-translations (will verify cvs status, upload scripts, and upload pages)

update-translations: always
	for f in $(TRANSLATIONS); do \
		echo $$f...; \
		sleep 5; \
		make $$f; \
	done

upload-translations: always
	for f in $(TRANSLATIONS); do \
		cvs status $$f | grep 'Status: Up-to-date'; \
		wikiput -u cvs -s update http://www.oddmuse.org/cgi-bin/oddmuse/raw/$$f < $$f; \
		emacswiki-upload cgi-bin $$f; \
	done

%-utf8.pl: always
	f=`basename $@` && wget -q http://www.oddmuse.org/cgi-bin/oddmuse/raw/$$f -O $@.wiki
	grep '^\(#\|\$$\)' $@.wiki > $@-new
	perl oddtrans -l $@ -l $@.wiki wiki.pl $(MODULES) >> $@-new && mv $@-new $@

.PHONY: always

deb:
	equivs-build control

install:
	@echo This only installs the deb file, not the script itself.
	dpkg -i oddmuse*.deb

test:
	perl test.pl
	echo -e "\007"

package-upload: debian-$(VERSION).tar.gz debian-$(VERSION).tar.gz.sig
	curl -T "{debian-$(VERSION).tar.gz,debian-$(VERSION).tar.gz.sig}" \
	ftp://savannah.gnu.org/incoming/savannah/oddmuse/

package: debian-$(VERSION).tar.gz
	gpg --ascii --encrypt $<

debian-$(VERSION).tar.gz:
	rm -rf $(VERSION)
	mkdir $(VERSION)
	cp README FDL GPL wiki.pl $(VERSION)
	tar czf $@ $(VERSION)
