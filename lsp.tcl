#! /bin/sh
# -*- tcl -*- \
exec tclsh "$0" ${1+"$@"}

# Tcl implementation of a LSP server based on: https://www.youtube.com/watch?v=YsdlcQoHqPY&ab_channel=TJDeVries

lappend auto_path [file dirname [info script]]
package require lsp_server

proc didOpen {uri text} {
    global textDocuments
    set textDocuments($uri) $text
}

proc didChange {uri text} {
    global textDocuments
    set textDocuments($uri) $text
}

proc didSave {uri} {
    global textDocuments
}

proc didClose {uri} {
    global textDocuments
    unset -nocomplain textDocuments($uri)
}

proc definition {id uri line character} {
    set d [dict create uri file:///home/josd/Development/src/lsp/def.tcl \
               startline $line \
               startcharacter $character \
               endline $line \
               endcharacter [expr {$character + 5}]]
    return $d
}

proc hover {id uri line character} {
    return "hover test @ $line.$character"
}

proc document_link {id uri} {
    global textDocuments
    set urifnm [string range $uri 7 end]
    set uridir [file dirname $urifnm]
    set links {}
    if {[info exists textDocuments($uri)]} {
        set linkline 0
        foreach l [split $textDocuments($uri) \n] {
            if {[string match "input *" [string trim $l]]} {
                foreach fnm [lrange $l 1 end] {
                    set found 0
                    set refdir $uridir
                    for {set i 0} {$i < 5} {incr i} {
                        set reffnm [file join $refdir $fnm]
                        if {[file exists $reffnm]} {
                            set found 1
                            break
                        } else {
                            set refdir [file dirname $refdir]
                        }
                    }
                    if {!$found} {
                        continue
                    }
                    set definitionuri file://$reffnm
                    set charbegin [string first $fnm $l]
                    set charend [expr {$charbegin + [string length $fnm]}]
                    lappend links [dict create uri $definitionuri \
                                       line_begin $linkline \
                                       character_begin $charbegin \
                                       line_end $linkline \
                                       character_end $charend \
                                       tooltip "Tooltip for info link"]
                }
            }
            if {[regexp {^source (.*)$} [string trimright $l] - fnm] && [file exists $fnm]} {
                set definitionuri file://[file join $uridir $fnm]
                set charbegin [string first $fnm $l]
                set charend [expr {$charbegin + [string length $fnm]}]
                lappend links [dict create uri $definitionuri \
                                   line_begin $linkline \
                                   character_begin $charbegin \
                                   line_end $linkline \
                                   character_end $charend \
                                   tooltip "Tooltip for info link"]
            }
            if {[regexp {^source \[search (.*)\]$} [string trimright $l] - fnm]} {
                set found 0
                set refdir $uridir
                for {set i 0} {$i < 5} {incr i} {
                    set reffnm [file join $refdir $fnm]
                    if {[file exists $reffnm]} {
                        set found 1
                        break
                    } else {
                        set refdir [file dirname $refdir]
                    }
                }
                if {$found} {
                    set definitionuri file://$reffnm
                    set charbegin [string first $fnm $l]
                    set charend [expr {$charbegin + [string length $fnm]}]
                    lappend links [dict create uri $definitionuri \
                                       line_begin $linkline \
                                       character_begin $charbegin \
                                       line_end $linkline \
                                       character_end $charend \
                                       tooltip "Tooltip for info link"]
                }
            }
            incr linkline
        }
    }
    return $links
}

proc cancel {id} {
    puts stderr "cancelling request $id"
}

set lsp_server::handler(textDocument/didOpen) didOpen
set lsp_server::handler(textDocument/didChange) didChange
set lsp_server::handler(textDocument/didSave) didSave
set lsp_server::handler(textDocument/didClose) didClose
set lsp_server::handler(textDocument/hover) hover
#set lsp_server::handler(textDocument/definition) definition
#set lsp_server::handler(textDocument/documentLink) document_link
set lsp_server::handler(cancelRequest) cancel

lsp_server::start

vwait forever
