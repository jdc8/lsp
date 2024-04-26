tclp: tclp.tcl
	critcl -keep -debug all -pkg tclp.tcl

test: tclp
	tclsh test.tcl

clean:
	rm -Rf include lib
