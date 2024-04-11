# Tcl implementation of a LSP server based on: https://www.youtube.com/watch?v=YsdlcQoHqPY&ab_channel=TJDeVries

package require json
package require json::write

package provide lsp_server 0.1

namespace eval lsp_server {

    variable lsptclname "lsp_server"
    variable lsptclversion "0.1"

    variable requestdata ""
    variable requestlength 0
    variable contentdata ""
    variable debuglevel 1
    variable initialized 0
    set shuttingDown 0

    variable handler

    set lsperror(serverNotInitialized) -32002
    set lsperror(InternalError) -32603
    set lsperror(InvalidRequest) -32600

    proc debugPuts {msg {lvl 10}} {
        variable debuglevel
        if {$lvl <= $debuglevel} {
            puts stderr "Debug: $msg"
        }
    }

    proc errorResponse {requestdict errorcode errormsg} {
        variable lsperror
        if {[dict exists $requestdict id]} {
            set responsejson [json::write object \
                                  jsonrpc [json::write string "2.0"] \
                                  id [dict get $requestdict id] \
                                  error [json::write object \
                                             co [json::write string $lsperror($errorcode)] \
                                             message [json::write string $errormsg] \
                                            ] \
                                 ]
            debugPuts "process [dict get $requestdict method] error response" 1
            debugPuts "process [dict get $requestdict method] error response json = $responsejson" 2
            putData $responsejson
        }
    }

    proc initializeRequest {requestdict} {
        variable handler
        variable lsptclname
        variable lsptclversion
        debugPuts "process initialize request" 1
        # As an example extract client name and version
        if {[dict exists $requestdict params clientInfo name]} {
            debugPuts "process initialize clientInfo name = '[dict get $requestdict params clientInfo name]'" 2
        }
        if {[dict exists $requestdict params clientInfo version]} {
            debugPuts "process initialize clientInfo version = '[dict get $requestdict params clientInfo version]'" 2
        }
        set responsejson [json::write object \
                              jsonrpc [json::write string "2.0"] \
                              id [dict get $requestdict id] \
                              result [json::write object \
                                          serverInfo [json::write object \
                                                          name [json::write string $lsptclname] \
                                                          version [json::write string $lsptclversion] \
                                                         ] \
                                          capabilities [json::write object \
                                                            textDocumentSync 1 \
                                                            hoverProvider [expr {[info exists handler(textDocument/hover)] ? "true" : "false"}] \
                                                            definitionProvider [expr {[info exists handler(textDocument/definition)] ? "true" : "false"}] \
                                                            documentLinkProvider [expr {[info exists handler(textDocument/documentLink)] ? "true" : "false"}] \
                                                           ] \
                                         ] \
                             ]
        debugPuts "process initialize response json = $responsejson" 2
        putData $responsejson
    }

    proc initializedNotification {requestdict} {
        variable initialized
        variable handler
        debugPuts "process initialized notification" 1
        set initialized 1
    }

    proc textDocumentDidOpenRequest {requestdict} {
        variable handler
        debugPuts "process textDocument/didOpen notification" 1
        if {[info exists handler(textDocument/didOpen)]} {
            try {
                uplevel #0 [list {*}$handler(textDocument/didOpen) [dict get $requestdict params textDocument uri] [dict get $requestdict params textDocument text]]
            }
        }
    }

    proc textDocumentDidChangeRequest {requestdict} {
        variable handler
        debugPuts "process textDocument/didOpen notification" 1
        if {[info exists handler(textDocument/didChange)]} {
            # Assume first content change item has full text
            try {
                uplevel #0 [list {*}$handler(textDocument/didChange) [dict get $requestdict params textDocument uri] [dict get [lindex [dict get $requestdict params contentChanges] 0] text]]
            }
        }
    }

    proc textDocumentDidSaveRequest {requestdict} {
        variable handler
        debugPuts "process textDocument/didSave notification" 1
        if {[info exists handler(textDocument/didSave)]} {
            try {
                uplevel #0 [list {*}$handler(textDocument/didSave) [dict get $requestdict params textDocument uri]]
            }
        }
    }

    proc textDocumentDidCloseRequest {requestdict} {
        variable handler
        debugPuts "process textDocument/didClose notification" 1
        if {[info exists handler(textDocument/didClose)]} {
            try {
                uplevel #0 [list {*}$handler(textDocument/didClose) [dict get $requestdict params textDocument uri]]
            }
        }
    }

    proc textDocumentHoverRequest {requestdict} {
        variable handler
        debugPuts "process textDocument/hover request" 1
        if {[info exists handler(textDocument/hover)]} {
            try {
                set uri [dict get $requestdict params textDocument uri]
                set line [dict get $requestdict params position line]
                set character [dict get $requestdict params position character]
                set hovertext [uplevel #0 [list {*}$handler(textDocument/hover) [dict get $requestdict id] $uri $line $character]]
                set responsejson [json::write object \
                                      jsonrpc [json::write string "2.0"] \
                                      id [dict get $requestdict id] \
                                      result [json::write object \
                                                  contents [json::write string $hovertext] \
                                                 ] \
                                     ]
                debugPuts "process textDocument/hover response id = [dict get $requestdict id]" 1
                debugPuts "process textDocument/hover response json = $responsejson" 2
                putData $responsejson
            } on error msg {
                errorResponse $requestdict InternalError $msg
            }
        }
    }

    proc textDocumentDefinitionRequest {requestdict} {
        variable handler
        debugPuts "process textDocument/definition request" 1
        if {[info exists handler(textDocument/definition)]} {
            try {
                set uri [dict get $requestdict params textDocument uri]
                set line [dict get $requestdict params position line]
                set character [dict get $requestdict params position character]
                set definition [uplevel #0 [list {*}$handler(textDocument/definition) [dict get $requestdict id] $uri $line $character]]
                set responsejson [json::write object \
                                      jsonrpc [json::write string "2.0"] \
                                      id [dict get $requestdict id] \
                                      result [json::write object \
                                                  uri [json::write string [dict get $definition uri]] \
                                                  range [json::write object \
                                                             start [json::write object \
                                                                        line [dict get $definition startline] \
                                                                        character [dict get $definition startcharacter] \
                                                                       ] \
                                                             end [json::write object \
                                                                      line [dict get $definition endline] \
                                                                      character [dict get $definition endcharacter] \
                                                                     ] \
                                                            ] \
                                                 ] \
                                     ]
                debugPuts "process textDocument/definition response id = [dict get $requestdict id]" 1
                debugPuts "process textDocument/definition response json = $responsejson" 2
                putData $responsejson
            } on error msg {
                errorResponse $requestdict InternalError $msg
            }
        }
    }

    proc textDocumentDocumentLinkRequest {requestdict} {
        variable handler
        debugPuts "process textDocument/documentLink request" 1
        if {[info exists handler(textDocument/documentLink)]} {
            try {
                set uri [dict get $requestdict params textDocument uri]
                set links [uplevel #0 [list {*}$handler(textDocument/documentLink) [dict get $requestdict id] $uri]]
                set json_links {}
                foreach d $links {
                    lappend json_links [json::write object \
                                            target [json::write string [dict get $d uri]] \
                                            range [json::write object \
                                                       start [json::write object \
                                                                  line [dict get $d line_begin] \
                                                                  character [dict get $d character_begin] \
                                                                 ] \
                                                       end [json::write object \
                                                                line [dict get $d line_end] \
                                                                character [dict get $d character_end] \
                                                               ] \
                                                      ] \
                                            tooltip [json::write string [dict get $d tooltip]] \
                                           ] \
                    }
                set responsejson [json::write object \
                                      jsonrpc [json::write string "2.0"] \
                                      id [dict get $requestdict id] \
                                      result [json::write array {*}$json_links] \
                                     ]
                debugPuts "process textDocument/documentLink response id = [dict get $requestdict id]" 1
                debugPuts "process textDocument/documentLink response json = $responsejson" 2
                putData $responsejson
            } on error msg {
                errorResponse $requestdict InternalError $msg
            }
        }
    }

    proc shutdownRequest {requestdict} {
        variable handler
        variable shuttingDown
        debugPuts "process shutdown request" 1
        if {[info exists handler(shutdown)]} {
            try {
                uplevel #0 [list {*}$handler(shutdown) [dict get $requestdict id]]
           } on error {
                errorResponse $requestdict InternalError $msg
            }
        }
        set shutdown 1
        set responsejson [json::write object \
                              jsonrpc [json::write string "2.0"] \
                              id [dict get $requestdict id] \
                             ]
        debugPuts "process textDocument/shutdown response id = [dict get $requestdict id]" 1
        debugPuts "process textDocument/shutdown response json = $responsejson" 2
        putData $responsejson
    }

    proc exitNotification {responsejson} {
        debugPuts "process exit notification" 1
        exit
    }

    proc cancelNotification {requestdict} {
        variable handler
        debugPuts "process cancel notification" 1
        if {[info exists handler(cancelRequest)]} {
            try {
                uplevel #0 [list {*}$handler(cancelRequest) [dict get $requestdict params id]]
            }
        }
    }

    proc processRequest {} {
        variable contentdata
        variable lsptclname
        variable lsptclversion
        variable handler
        variable initialized
        variable shuttingDown
        debugPuts "process request = $contentdata" 2
        set requestdict [json::json2dict $contentdata]
        debugPuts "process json requestdict = $requestdict"
        set requestmethod [dict get $requestdict method]
        set requestid [expr {[dict exists $requestdict id] ? [dict get $requestdict id] : -1}]
        debugPuts "processes method = $requestmethod id = $requestid" 1
        if {!$initialized && $requestmethod ni {initialize initialized}} {
            errorResponse $requestdict serverNotInitialized "The server is not initialized yet."
            return
        }
        switch -exact -- $requestmethod {
            initialize { initializeRequest $requestdict }
            initialized { initializedNotification $requestdict }
            textDocument/didOpen { textDocumentDidOpenRequest $requestdict }
            textDocument/didChange { textDocumentDidChangeRequest $requestdict }
            textDocument/didSave { textDocumentDidSaveRequest $requestdict }
            textDocument/didClose { textDocumentDidCloseRequest $requestdict }
            textDocument/hover { textDocumentHoverRequest $requestdict }
            textDocument/definition { textDocumentDefinitionRequest $requestdict }
            textDocument/documentLink { textDocumentDocumentLinkRequest $requestdict }
            shutdown { shutdownRequest $requestdict }
            exit { exitNotification $requestdict }
            default {
                errorResponse $requestdict InvalidRequest "not processing unknown request/notification $requestmethod"
            }
        }
    }

    proc putData {content} {
        set msg "Content-Length: [string length $content]\r\n\r\n$content"
        debugPuts "put data: msg=$msg"
        puts -nonewline stdout $msg
        flush stdout
    }

    proc _getData {} {
        variable requestdata
        variable requestlength
        variable contentdata
        set data [read stdin]
        debugPuts "data read from stdin: size=[string length $data] data='$data'"
        if {[eof stdin]} {
            debugPuts "eof stdin"
            fileevent stdin readable {}
        }
        append requestdata $data
        debugPuts "requestdata='$requestdata'"
        # Look for request length
        if {[regexp {^Content-Length: ([[:digit:]]+)} $requestdata - requestlength]} {
            debugPuts "request length found: $requestlength"
            # Is full request received already?
            set idx1 [string first "\r\n" $requestdata]
            debugPuts "first separator found at $idx1"
            set idx2 [string first "\r\n" $requestdata [expr {$idx1 + 2}]]
            if {$idx2 > $idx1} {
                debugPuts "second separator found at $idx2"
                set receivedlength [expr {[string length $requestdata] - $idx2 - 2}]
                debugPuts "received content length = $receivedlength"
                if {$receivedlength >= $requestlength} {
                    debugPuts "full content received"
                    set contentdata [string range $requestdata [expr {$idx2 + 2}] [expr {$idx2 + 2 + $requestlength - 1}]]
                    debugPuts "contentdata = $contentdata"
                    set requestdata [string range $requestdata [expr {$idx2 + 2 + $requestlength}] end]
                    debugPuts "requestdata = $requestdata"
                    processRequest
                }
            } else {
                debugPuts "second separator not found yet"
                return
            }
        } else {
            debugPuts "request length not found"
            return
        }
    }

    proc getData {} {
        fileevent stdin readable {}
        _getData
        fileevent stdin readable [list lsp_server::getData]
    }

    proc start {} {
        fconfigure stdin -blocking 0 -encoding binary -translation binary
        fileevent stdin readable [list lsp_server::getData]
        fconfigure stdout -blocking 0 -encoding binary -translation binary
    }
}
