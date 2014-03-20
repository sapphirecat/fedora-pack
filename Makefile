ALL := bin/make-provisioner

all: $(ALL)

clean:
	-rm $(ALL)

bin/make-provisioner: src/make-provisioner/host.pl src/make-provisioner/guest.sh
	cat $^ > $@
	chmod +x $@
	perl -c $@

.PHONY: all clean
