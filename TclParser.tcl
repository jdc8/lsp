
package require critcl-tclp
package provide TclParser 0.1

oo::class create TclParser {

    variable fileName
    variable script
    variable lineStarts
    variable commentLocations
    variable procLocations

    constructor {args} {
        set fileName ""
        set lineStarts {}
        set commentLocations {}
        set procLocations {}
	foreach {k v} $args {
	    set $k $v
	}
    }

    method configure {args} {
	if {[llength $args] == 1} {
	    return [set [lindex $args 0]]
	} elseif {([llength $args] % 2) == 0} {
            foreach {k v} $args {
                set $k $v
            }
        } else {
            error "Wrong number of arguments: use 'TclParserObject configure <key>' or 'TclParserObject configure <key> <value> ?<key> <value> ...?'"
        }
    }

    method cget {key} {
        return [set $key]
    }

    # Collect all line start offsets
    method LineCharInit {} {
        set L 0
        set P 0
        foreach l [split $script \n] {
            lappend lineStarts $P
            incr P [expr {[string length $l] + 1}]
            incr L
        }
    }

    # Convert offset within script into line number and charater offset within line
    method LineChar {offset} {
        set L 0
        foreach pos [lrange $lineStarts 1 end] {
            if {$offset < $pos} {
                break
            }
            incr L
        }
        set P [expr {$offset - [lindex $lineStarts $L]}]
        return [dict create line $L character $P]
    }

    # Convert line number and character offset within line into offset within script
    method Offset {line character} {
        if {$line < [llength $lineStarts]} {
            return [expr {[lindex $lineStarts $line] + $character}]
        } else {
            return -1
        }
    }

    # Extract a string from the script
    method Extract {offset size} {
        return [string range $script $offset [expr {$offset + $size - 1}]]
    }

    #
    method ParseScript {} {
        set commandOffset 0
        while {$commandOffset < [string length $script]} {
            set d [tclp command $script $commandOffset]
            # Look for comments
            if {[dict get $d commentSize]} {
                set commentPositiomStart [my LineChar [dict get $d commentStart]]
                set commentPositionEnd [my LineChar [expr {[dict get $d commentStart] + [dict get $d commentSize]}]]
                lappend commentLocations [dict create start $commentPositiomStart end $commentPositionEnd]
            }
            # Command name if first token
            set commandNameToken [lindex [dict get $d tokens] 0]
            set commandName [my Extract [dict get $commandNameToken start] [dict get $commandNameToken size]]
            switch -exact -- $commandName {
                "proc" {
                    # Proc name is second token
                    set commandNameComponentCount [dict get $commandNameToken numComponents]
                    set procNameToken [lindex [dict get $d tokens] [expr {$commandNameComponentCount + 1}]]
                    set procName [my Extract [dict get $procNameToken start] [dict get $procNameToken size]]
                    set procPositionStart [my LineChar [dict get $procNameToken start]]
                    set procPositionEnd [my LineChar [expr {[dict get $procNameToken start] + [dict get $procNameToken size]}]]
                    lappend procLocations [dict create name $procName start $procPositionStart end $procPositionEnd]
                }
            }
            # Continue with next command
            set commandOffset [expr {[dict get $d commandStart] + [dict get $d commandSize]}]
        }
    }

    method getStringAtPosition {line character} {
        set offset [my Offset $line $character]
        if {$offset < 0} {
            return ""
        }
        set idx0 [string wordstart $script $offset]
        set idx1 [string wordend $script $offset]
        if {$idx0 < 0} {
            set idx0 0
        }
        if {$idx1 < 0} {
            set idx1 [string length $script]
        }
        return [string range $script $idx0 $idx1-1]
    }

    method getProcLocation {name} {
        foreach p $procLocations {
            if {[dict get $p name] eq $name} {
                return $p
            }
        }
        return ""
    }

    # Return location when the word pointed to by line and character is defined
    method getDefinition {line character} {
        set word [my getStringAtPosition $line $character]
        return [my getProcLocation $word]
   }

    method analyse {} {
        set lineStarts {}
        set commentLocations {}
        set procLocations {}
        set f [open $fileName r]
        set script [read $f]
        close $f
        my LineCharInit
        my ParseScript
    }
}

if 0 {
    set parsers {}
    foreach fnm $argv {
        lappend parsers [set p [TclParser new fileName $fnm]]
        $p analyse
    }

    foreach p $parsers {
        puts "File: [$p cget fileName]"
        puts "  Comments: [$p cget commentLocations]"
        puts "  Procs: [$p cget procLocations]"
    }

    foreach p $parsers {
        $p destroy
    }

    exit
}
