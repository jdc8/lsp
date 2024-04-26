#! /bin/sh
# -*- tcl -*- \
exec tclsh "$0" ${1+"$@"}

# Tcl implementation of a LSP server based on: https://www.youtube.com/watch?v=YsdlcQoHqPY&ab_channel=TJDeVries

lappend auto_path [file dirname [info script]] [file join [file dirname [info script]] lib]
package require lsp_server
package require TclParser

package require uri

proc didOpen {uri text} {
    global textDocuments
    if {[info exists textDocuments($uri)]} {
        $textDocuments($uri) destroy
    }
    set urid [uri::split $uri]
    puts stderr "use $urid"
    set textDocuments($uri) [TclParser new fileName [dict get $urid path]]
    $textDocuments($uri) analyse
}

proc didChange {uri text} {
    didOpen $uri $text
}

proc didSave {uri} {
}

proc didClose {uri} {
    global textDocuments
    if {[info exists textDocuments($uri)]} {
        $textDocuments($uri) destroy
        unset -nocomplain textDocuments($uri)
    }
}

proc definition {id uri line character} {
    global textDocuments
    if {[info exists textDocuments($uri)]} {
        set pd [$textDocuments($uri) getDefinition $line $character]
        if {[string length $pd]} {
            return [dict create uri [uri::join scheme file path [$textDocuments($uri) cget fileName]] \
                        startline [dict get $pd start line] \
                        startcharacter [dict get $pd start character] \
                        endline [dict get $pd end line] \
                        endcharacter [dict get $pd end character]]
        } else {
            error "Could not find definition of '$word' at position $line.$character"
        }
    } else {
            error "Could not find definition of word at position $line.$character"
    }
}

proc hover {id uri line character} {
    global textDocuments
    if {[info exists textDocuments($uri)]} {
        set pd [$textDocuments($uri) getDefinition $line $character]
        if {[string length $pd]} {
            set result "proc defined in [uri::join scheme file path [$textDocuments($uri) cget fileName]] at position [dict get $pd start line].[dict get $pd start character]"
            if {[dict get $pd arguments] ne ""} {
                append result " with these arguments: [dict get $pd arguments]"
            }
            return $result
        }
    }
    return "hover test @ $line.$character"
}

proc document_link {id uri} {
    global textDocuments
    set urifnm [string range $uri 7 end]
    set uridir [file dirname $urifnm]
    set links {}
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
set lsp_server::handler(textDocument/definition) definition
set lsp_server::handler(textDocument/documentLink) document_link
set lsp_server::handler(cancelRequest) cancel

lsp_server::start
