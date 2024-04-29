set TclParserStandAlone 0

if {$TclParserStandAlone} {
    lappend auto_path [file dirname [info script]] [file join [file dirname [info script]] lib]
}

package require critcl-tclp
package provide TclParser 0.1

oo::class create TclParser {

    variable script
    variable lineStarts
    variable commentLocations
    variable procLocations
    variable classLocations
    variable constructorLocations
    variable methodLocations

    constructor {args} {
        set lineStarts {}
        set commentLocations {}
        set procLocations {}
        set classLocations {}
        set constructorLocations {}
        set methodLocations {}
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

    # Split token list and group components. Parse as a non-nested list of tokens.
    method GroupTokens {tokens} {
        set groups {}
        for {set i 0} {$i < [llength $tokens]} {incr i} {
            set t [lindex $tokens $i]
            set numComponents [dict get $t numComponents]
            lappend groups [list $t {*}[lrange $tokens [expr {$i+1}] [expr {$i + $numComponents}]]]
            incr i $numComponents
        }
        return $groups
    }

    # Look for SIMPLE_WORD + TEXT or TEXT or WORD
    method GetSimpleWordToken {tokens} {
        set token [lindex $tokens 0]
        if {[dict get $token type] eq "TEXT"} {
            return $token
        }
        if {[dict get $token type] eq "WORD"} {
            return $token
        }
        if {[dict get $token type] in "SIMPLE_WORD" && [dict get $token numComponents] == 1} {
            set token [lindex $tokens 1]
            if {[dict get $token type] eq "TEXT"} {
                return $token
            }
        }
        return ""
    }

    # Parse the script
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
            puts "Tokenlist:"
            puts [dict get $d tokens]
            set groupedTokens [my GroupTokens [dict get $d tokens]]
            puts "Grouped tokens:"
            puts [join $groupedTokens \n]
            # Command name if first token
            set commandNameToken [my GetSimpleWordToken [lindex $groupedTokens 0]]
            if {$commandNameToken ne ""} {
                set commandName [my Extract [dict get $commandNameToken start] [dict get $commandNameToken size]]
                puts "commandName=$commandName"
                switch -exact -- $commandName {
                    "proc" - "::proc" {
                        # Proc name is second token
                        set procNameToken [my GetSimpleWordToken [lindex $groupedTokens 1]]
                        if {$procNameToken ne ""} {
                            set procName [my Extract [dict get $procNameToken start] [dict get $procNameToken size]]
                            set procPositionStart [my LineChar [dict get $procNameToken start]]
                            set procPositionEnd [my LineChar [expr {[dict get $procNameToken start] + [dict get $procNameToken size]}]]
                            # Proc arguments are in third token
                            set arguments ""
                            set argumentsToken [my GetSimpleWordToken [lindex $groupedTokens 2]]
                            if {$argumentsToken ne ""} {
                                set arguments [my Extract [dict get $argumentsToken start] [dict get $argumentsToken size]]
                            }
                            lappend procLocations [dict create name $procName start $procPositionStart end $procPositionEnd arguments $arguments]
                        }
                    }
                    "method" - "::method" {
                        # Method name is second token
                        set methodNameToken [my GetSimpleWordToken [lindex $groupedTokens 1]]
                        if {$methodNameToken ne ""} {
                            set methodName [my Extract [dict get $methodNameToken start] [dict get $methodNameToken size]]
                            set methodPositionStart [my LineChar [dict get $methodNameToken start]]
                            set methodPositionEnd [my LineChar [expr {[dict get $methodNameToken start] + [dict get $methodNameToken size]}]]
                            # Method arguments are in third token
                            set arguments ""
                            set argumentsToken [my GetSimpleWordToken [lindex $groupedTokens 2]]
                            if {$argumentsToken ne ""} {
                                set arguments [my Extract [dict get $argumentsToken start] [dict get $argumentsToken size]]
                            }
                            lappend methodLocations [dict create name $methodName start $methodPositionStart end $methodPositionEnd arguments $arguments]
                        }
                    }
                    "constructor" - "::constructor" {
                        set constructorPositionStart [my LineChar [dict get $commandNameToken start]]
                        set constructorPositionEnd [my LineChar [expr {[dict get $commandNameToken start] + [dict get $commandNameToken size]}]]
                        # Constructor arguments are in second token
                        set arguments ""
                        set argumentsToken [my GetSimpleWordToken [lindex $groupedTokens 1]]
                        if {$argumentsToken ne ""} {
                            set arguments [my Extract [dict get $argumentsToken start] [dict get $argumentsToken size]]
                        }
                        lappend constructorLocations [dict create name constructor start $constructorPositionStart end $constructorPositionEnd arguments $arguments]
                    }
                    "oo::class" - "::oo::class" {
                        # class command name is second token
                        set classCommandNameToken [my GetSimpleWordToken [lindex $groupedTokens 1]]
                        if {$classCommandNameToken ne ""} {
                            set classCommandName [my Extract [dict get $classCommandNameToken start] [dict get $classCommandNameToken size]]
                            switch -exact -- $classCommandName {
                                "create" {
                                    # class name is third argument
                                    set classNameToken [my GetSimpleWordToken [lindex $groupedTokens 2]]
                                    if {$classNameToken ne ""} {
                                        set className [my Extract [dict get $classNameToken start] [dict get $classNameToken size]]
                                        set classPositionStart [my LineChar [dict get $classNameToken start]]
                                        set classPositionEnd [my LineChar [expr {[dict get $classNameToken start] + [dict get $classNameToken size]}]]
                                        # class definition is fourth argument
                                        set classBodyToken [my GetSimpleWordToken [lindex $groupedTokens 3]]
                                        set adjustedConstructorLocations {}
                                        set adjustedMethodLocations {}
                                        puts "CLASS BODY TOKEN = $classBodyToken"
                                        if {$classBodyToken ne ""} {
                                            set classBodyPositionStart [my LineChar [dict get $classBodyToken start]]
                                            set classBody [my Extract [dict get $classBodyToken start] [dict get $classBodyToken size]]
                                            set p [TclParser new script $classBody]
                                            $p analyse
                                            $p print stdout 3
                                            # Get info from body
                                            foreach cl [$p cget commentLocations] {
                                                lappend adjustedCommentLocations [dict create start [dict create line [expr {[dict get $cl start line] + [dict get $classBodyPositionStart line]}] character [dict get $cl start character]] end [dict create line [expr {[dict get $cl end line] + [dict get $classBodyPositionStart line]}] character [dict get $cl end character]]]
                                            }
                                            foreach cl [$p cget constructorLocations] {
                                                lappend adjustedConstructorLocations [dict create name constructor start [dict create line [expr {[dict get $cl start line] + [dict get $classBodyPositionStart line]}] character [dict get $cl start character]] end [dict create line [expr {[dict get $cl end line] + [dict get $classBodyPositionStart line]}] character [dict get $cl end character]] arguments [dict get $cl arguments]]
                                            }
                                            foreach ml [$p cget methodLocations] {
                                                 lappend adjustedMethodLocations [dict create name  [dict get $ml name] start [dict create line [expr {[dict get $ml start line] + [dict get $classBodyPositionStart line]}] character [dict get $ml start character]] end [dict create line [expr {[dict get $ml end line] + [dict get $classBodyPositionStart line]}] character [dict get $ml end character]] arguments [dict get $ml arguments]]
                                            }
                                            $p destroy
                                        }
                                        lappend commentLocations {*}$adjustedCommentLocations
                                        lappend classLocations [dict create name $className start $classPositionStart end $classPositionEnd constructors $adjustedConstructorLocations methods $adjustedMethodLocations]
                                    }
                                }
                            }
                        }
                    }
                    "namespace" - "::namespace" {
                    }
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
        set classLocations {}
        set constructorLocations {}
        set methodLocations {}
        my LineCharInit
        my ParseScript
    }

    method print {stream {lvl 0}} {
        puts "[string repeat ---- $lvl]TclParser:"
        puts "[string repeat ---- $lvl]  Comments"
        foreach l $commentLocations {
            puts "[string repeat ---- $lvl]      $l"
        }
        puts "[string repeat ---- $lvl]  Procs"
        foreach l $procLocations {
            puts "[string repeat ---- $lvl]      $l"
        }
        puts "[string repeat ---- $lvl]  Classes"
        foreach l $classLocations {
            puts "[string repeat ---- $lvl]      [dict get $l name]"
            puts "[string repeat ---- $lvl]      [dict get $l name]"
            puts "[string repeat ---- $lvl]          Constructors:"
            foreach cl [dict get $l constructors] {
                puts "[string repeat ---- $lvl]              $cl"
            }
            puts "[string repeat ---- $lvl]          Methods:"
            foreach cl [dict get $l methods] {
                puts "[string repeat ---- $lvl]              $cl"
            }
        }
    }
}

proc test {} {
}

if {$TclParserStandAlone} {

    set parsers {}
    foreach fnm $argv {
        set f [open $fnm r]
        set script [read $f]
        close $f
        lappend parsers [set p [TclParser new script $script]]
        $p analyse
    }

    foreach p $parsers fnm $argv {
        puts "File: $fnm"
        $p print stdout 1
    }

    foreach p $parsers {
        $p destroy
    }

    exit
}

unset -nocomplain TclParserStandAlone
