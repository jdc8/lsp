set TclParserStandAlone [expr {$argv0 eq "TclParser.tcl"}]

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
    variable destructorLocations
    variable memberVariableLocations
    variable methodLocations

    constructor {args} {
        set lineStarts {}
        set commentLocations {}
        set procLocations {}
        set classLocations {}
        set constructorLocations {}
        set destructorLocations {}
        set memberVariableLocations {}
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
    method lineChar {offset} {
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

    # Concat tokens without back slash tokens
    method ConcatWithoutBS {tokens} {
        set bsl {}
        set result ""
        foreach itoken $tokens {
            if {[dict get $itoken type] eq "BS"} {
                puts "BS @ [string length $result]: $itoken"
                lappend bsl [dict create offset [string length $result] bsToken $itoken]
            } else {
                append result [my Extract [dict get $itoken start] [dict get $itoken size]]
            }
        }
        return [dict create string $result bsPositions $bsl]
    }

    # Adjust start when taking back slash tokens into account
    method AdjustForBackslashTokens {d bsPositions offset} {
        set start [dict get $d start]
        set bsAdjustedStart $start
        foreach bsPosition $bsPositions {
            if {$start > [dict get $bsPosition offset]} {
                incr bsAdjustedStart [dict get $bsPosition bsToken size]
            }
        }
        return [dict set d start [expr {$bsAdjustedStart + $offset}]]
    }

    # Adjust start when taking back slash tokens into account
    method AdjustAllForBackslashTokens {cll bsPositions offset} {
        set result {}
        foreach cl $cll {
            lappend result [my AdjustForBackslashTokens $cl $bsPositions $offset]
        }
        return $result
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
    method ParseScript {what} {
        set commandOffset 0
        while {$commandOffset < [string length $script]} {
            set d [tclp command $script $commandOffset]
            # Look for comments
            if {[dict get $d commentSize]} {
                lappend commentLocations [dict create start [dict get $d commandStart] size [dict get $d commentSize]]
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
                switch -exact -- $what {
                    script {
                        switch -exact -- $commandName {
                            "proc" - "::proc" {
                                # Proc name is second token
                                set procNameToken [my GetSimpleWordToken [lindex $groupedTokens 1]]
                                if {$procNameToken ne ""} {
                                    set procName [my Extract [dict get $procNameToken start] [dict get $procNameToken size]]
                                    # Proc arguments are in third token
                                    set arguments ""
                                    set argumentsToken [my GetSimpleWordToken [lindex $groupedTokens 2]]
                                    if {$argumentsToken ne ""} {
                                        set arguments [my Extract [dict get $argumentsToken start] [dict get $argumentsToken size]]
                                    }
                                    lappend procLocations [dict create name $procName start [dict get $procNameToken start] size [dict get $procNameToken size] arguments $arguments]
                                }
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
                                                # class definition is fourth argument
                                                set classBodyToken [my GetSimpleWordToken [lindex $groupedTokens 3]]
                                                set adjustedCommentLocations {}
                                                set adjustedConstructorLocations {}
                                                set adjusteddestructorLocations {}
                                                set adjustedMemberVariableLocations {}
                                                set adjustedMethodLocations {}
                                                puts "CLASS BODY TOKEN = $classBodyToken"
                                                if {$classBodyToken ne ""} {
                                                    set classBody [my Extract [dict get $classBodyToken start] [dict get $classBodyToken size]]
                                                    # If body is a braced or double quoted string, remove the braces or double quotes and replace any back slashes in it.
                                                    # That will cause the line number to be off.
                                                    set bsPositions {}
                                                    set classBodyStartChar [string index $classBody 0]
                                                    if {$classBodyStartChar eq "\{" || $classBodyStartChar eq "\""} {
                                                        if {$classBodyStartChar eq "\{"} {
                                                            set bd [tclp braces $script [dict get $classBodyToken start]]
                                                        } else {
                                                            set bd [tclp quotedString $script [dict get $classBodyToken start]]
                                                        }
                                                        set pb [my ConcatWithoutBS [dict get $bd tokens]]
                                                        set classBody [dict get $pb string]
                                                        set bsPositions [dict get $pb bsPositions]
                                                        # Increment body start by one because brace got strippped
                                                        set classBodyStart [expr {[dict get $classBodyToken start] + 1}]
                                                    } else {
                                                        set classBodyStart [dict get $classBodyToken start]
                                                    }
                                                    # Now parse the body by calling the parser recursively
                                                    set p [TclParser new script $classBody]
                                                    $p analyse ooclassbody
                                                    $p print stdout 3
                                                    puts "bsPositions=$bsPositions"
                                                    # Get info from body and adjust line info for backslashes
                                                    set adjustedCommentLocations [my AdjustAllForBackslashTokens [$p cget commentLocations] $bsPositions $classBodyStart]
                                                    set adjustedConstructorLocations [my AdjustAllForBackslashTokens [$p cget constructorLocations] $bsPositions $classBodyStart]
                                                    set adjustedDestructorLocations [my AdjustAllForBackslashTokens [$p cget destructorLocations] $bsPositions $classBodyStart]
                                                    set adjustedMemberVariableLocations [my AdjustAllForBackslashTokens [$p cget memberVariableLocations] $bsPositions $classBodyStart]
                                                    set adjustedMethodLocations [my AdjustAllForBackslashTokens [$p cget methodLocations] $bsPositions $classBodyStart]
                                                    $p destroy
                                                }
                                                lappend commentLocations {*}$adjustedCommentLocations
                                                lappend classLocations \
                                                    [dict create \
                                                         name [my Extract [dict get $classNameToken start] [dict get $classNameToken size]] \
                                                         start [dict get $classNameToken start] \
                                                         size [dict get $classNameToken size] \
                                                         constructors $adjustedConstructorLocations \
                                                         destructors $adjustedDestructorLocations \
                                                         memberVariables $adjustedMemberVariableLocations \
                                                         methods $adjustedMethodLocations]
                                            }
                                        }
                                    }
                                }
                            }
                            "namespace" - "::namespace" {
                            }
                        }
                    }
                    ooclassbody {
                        switch -exact -- $commandName {
                            "method" {
                                # Method name is second token
                                set methodNameToken [my GetSimpleWordToken [lindex $groupedTokens 1]]
                                if {$methodNameToken ne ""} {
                                    set methodName [my Extract [dict get $methodNameToken start] [dict get $methodNameToken size]]
                                    # Method arguments are in third token
                                    set arguments ""
                                    set argumentsToken [my GetSimpleWordToken [lindex $groupedTokens 2]]
                                    if {$argumentsToken ne ""} {
                                        set arguments [my Extract [dict get $argumentsToken start] [dict get $argumentsToken size]]
                                    }
                                    lappend methodLocations [dict create name $methodName start [dict get $methodNameToken start] size [dict get $methodNameToken size] arguments $arguments]
                                }
                            }
                            "constructor" {
                                # Constructor arguments are in second token
                                set arguments ""
                                set argumentsToken [my GetSimpleWordToken [lindex $groupedTokens 1]]
                                if {$argumentsToken ne ""} {
                                    set arguments [my Extract [dict get $argumentsToken start] [dict get $argumentsToken size]]
                                }
                                lappend constructorLocations [dict create name constructor start [dict get $commandNameToken start] size [dict get $commandNameToken size] arguments $arguments]
                            }
                            "destructor" {
                                # Destructor has no arguments
                                lappend destructorLocations [dict create name destructor start [dict get $commandNameToken start] size [dict get $commandNameToken size]]
                            }
                            "variable" {
                                # Variable name is second token
                                set variableNameToken [my GetSimpleWordToken [lindex $groupedTokens 1]]
                                if {$variableNameToken ne ""} {
                                    set variableName [my Extract [dict get $variableNameToken start] [dict get $variableNameToken size]]
                                    lappend memberVariableLocations [dict create name $variableName start [dict get $variableNameToken start] size [dict get $variableNameToken size]]
                                }
                            }
                        }
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

    method analyse {{what script}} {
        set lineStarts {}
        set commentLocations {}
        set procLocations {}
        set classLocations {}
        set constructorLocations {}
        set destructorLocations {}
        set memberVariableLocations {}
        set methodLocations {}
        my LineCharInit
        my ParseScript $what
    }

    # Nicely print parser result
    method print {stream {lvl 0}} {
        puts "[string repeat ---- $lvl]TclParser:"
        puts "[string repeat ---- $lvl]  Comments"
        foreach l $commentLocations {
            puts "[string repeat ---- $lvl]      @ [my lineChar [dict get $l start]]"
        }
        puts "[string repeat ---- $lvl]  Procs"
        foreach l $procLocations {
            puts "[string repeat ---- $lvl]      [dict get $l name] @ [my lineChar [dict get $l start]]"
        }
        puts "[string repeat ---- $lvl]  Classes"
        foreach l $classLocations {
            puts "[string repeat ---- $lvl]      [dict get $l name] @ [my lineChar [dict get $l start]]"
            puts "[string repeat ---- $lvl]          Constructors:"
            foreach cl [dict get $l constructors] {
                puts "[string repeat ---- $lvl]              [dict get $cl name] @ [my lineChar [dict get $cl start]]"
            }
            puts "[string repeat ---- $lvl]          Destructors:"
            foreach cl [dict get $l destructors] {
                puts "[string repeat ---- $lvl]              [dict get $cl name] @ [my lineChar [dict get $cl start]]"
            }
            puts "[string repeat ---- $lvl]          Member variables:"
            foreach cl [dict get $l memberVariables] {
                puts "[string repeat ---- $lvl]              [dict get $cl name] @ [my lineChar [dict get $cl start]]"
            }
            puts "[string repeat ---- $lvl]          Methods:"
            foreach cl [dict get $l methods] {
                puts "[string repeat ---- $lvl]              [dict get $cl name] @ [my lineChar [dict get $cl start]]"
            }
        }
    }
}

proc test {s d f} {
    # test comment in a proc
    dict create nm \
        a b \
        c d \
        e f]
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
