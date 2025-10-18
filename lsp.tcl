#!/usr/bin/env tclsh
# TCL Language Server Protocol Implementation
# Compatible with Neovim, VS Code, and other LSP clients

package require json 1.3.4

# Global state
set ::initialized false
set ::server_capabilities {}

# ============================================================================
# Message Transport Layer (LSP Base Protocol)
# ============================================================================

proc read_message {} {
    set content_length 0
    set headers {}

    # Read headers until blank line
    while {[gets stdin line] >= 0} {
        set line [string trimright $line "\r"]

        if {$line eq ""} {
            break
        }

        if {[regexp {^Content-Length:\s*(\d+)} $line -> length]} {
            set content_length $length
        }

        lappend headers $line
    }

    # Read the JSON content
    if {$content_length > 0} {
        set content [read stdin $content_length]
        return $content
    }

    return ""
}

proc send_message {content} {
    set length [string length $content]
    puts "Content-Length: $length\r"
    puts "\r"
    puts -nonewline $content
    flush stdout
}

proc send_response {id result} {
    set response [dict create \
        jsonrpc "2.0" \
        id $id \
        result $result \
    ]

    set json_response [json::dict2json $response]
    send_message $json_response
}

proc send_error_response {id code message {data ""}} {
    set error [dict create \
        code $code \
        message $message \
    ]

    if {$data ne ""} {
        dict set error data $data
    }

    set response [dict create \
        jsonrpc "2.0" \
        id $id \
        error $error \
    ]

    set json_response [json::dict2json $response]
    send_message $json_response
}

proc send_notification {method params} {
    set notification [dict create \
        jsonrpc "2.0" \
        method $method \
        params $params \
    ]

    set json_notification [json::dict2json $notification]
    send_message $json_notification
}

# ============================================================================
# Utility Functions
# ============================================================================

proc uri_to_path {uri} {
    # Convert file:// URI to local path
    if {[string match "file://*" $uri]} {
        set path [string range $uri 7 end]
        # URL decode
        set path [regsub -all {%([0-9A-Fa-f]{2})} $path {[format %c 0x\1]}]
        return [subst $path]
    }
    return $uri
}

proc path_to_uri {path} {
    # Convert local path to file:// URI
    return "file://$path"
}

proc log_debug {message} {
    # Send log notification to client
    send_notification "window/logMessage" [dict create \
        type 4 \
        message "TCL-LSP: $message" \
    ]
}

# ============================================================================
# TCL Language Analysis
# ============================================================================

proc get_tcl_keywords {} {
    return {
        if then else elseif
        while for foreach
        switch case default
        proc return break continue
        set unset global upvar variable
        puts gets read write open close
        file glob
        string list array dict
        regexp regsub
        catch error throw try finally
        namespace package
        source load auto_load
        rename trace info
        clock exec eval expr
        format scan binary encoding
        join split
        lappend lindex linsert lreplace llength lrange lsearch lsort
        append concat
        subst
        pwd cd
        exit
    }
}

proc get_tcl_completions {file_path position} {
    set items {}

    # Add TCL keywords
    foreach keyword [get_tcl_keywords] {
        lappend items [dict create \
            label $keyword \
            kind 14 \
            detail "TCL keyword" \
            documentation "Built-in TCL command" \
        ]
    }

    # Try to read file and analyze for procedures
    if {[file exists $file_path]} {
        if {[catch {
            set fd [open $file_path r]
            set content [read $fd]
            close $fd

            # Find procedure definitions
            foreach line [split $content "\n"] {
                if {[regexp {^\s*proc\s+(\w+)} $line -> proc_name]} {
                    lappend items [dict create \
                        label $proc_name \
                        kind 3 \
                        detail "User procedure" \
                        documentation "Procedure defined in current file" \
                    ]
                }
            }
        } err]} {
            log_debug "Error reading file $file_path: $err"
        }
    }

    return $items
}

proc get_hover_info {file_path position} {
    # This is a simplified hover implementation
    # In a real implementation, you'd parse the file and find the symbol at position

    set line_num [dict get $position line]
    set char_num [dict get $position character]

    if {[file exists $file_path]} {
        if {[catch {
            set fd [open $file_path r]
            set lines [split [read $fd] "\n"]
            close $fd

            if {$line_num < [llength $lines]} {
                set line [lindex $lines $line_num]

                # Simple word extraction at position
                set word ""
                if {$char_num < [string length $line]} {
                    # Find word boundaries
                    set start $char_num
                    set end $char_num

                    while {$start > 0 && [string is wordchar [string index $line [expr {$start - 1}]]]} {
                        incr start -1
                    }

                    while {$end < [string length $line] && [string is wordchar [string index $line $end]]} {
                        incr end
                    }

                    set word [string range $line $start [expr {$end - 1}]]
                }

                # Provide basic documentation for known commands
                if {$word in [get_tcl_keywords]} {
                    return "**$word** - TCL built-in command\n\nFor detailed help, use: `man n $word`"
                }
            }
        } err]} {
            log_debug "Error getting hover info: $err"
        }
    }

    return ""
}

# ============================================================================
# LSP Request Handlers
# ============================================================================

proc handle_initialize {id params} {
    log_debug "Initialize request received"

    set ::initialized true

    set capabilities [dict create \
        textDocumentSync 1 \
        completionProvider [dict create \
            resolveProvider false \
            triggerCharacters [list "." "$" "\["] \
        ] \
        hoverProvider true \
        definitionProvider false \
        referencesProvider false \
        documentFormattingProvider false \
        documentRangeFormattingProvider false \
    ]

    set result [dict create \
        capabilities $capabilities \
        serverInfo [dict create \
            name "tcl-lsp" \
            version "1.0.0" \
        ] \
    ]

    send_response $id $result
    log_debug "Initialize response sent"
}

proc handle_initialized {params} {
    log_debug "Client initialized"
}

proc handle_shutdown {id params} {
    log_debug "Shutdown request received"
    send_response $id null
}

proc handle_exit {params} {
    log_debug "Exit notification received"
    exit 0
}

proc handle_completion {id params} {
    set document [dict get $params textDocument]
    set position [dict get $params position]
    set uri [dict get $document uri]

    set file_path [uri_to_path $uri]
    set completions [get_tcl_completions $file_path $position]

    set result [dict create \
        isIncomplete false \
        items $completions \
    ]

    send_response $id $result
}

proc handle_hover {id params} {
    set document [dict get $params textDocument]
    set position [dict get $params position]
    set uri [dict get $document uri]

    set file_path [uri_to_path $uri]
    set hover_info [get_hover_info $file_path $position]

    if {$hover_info ne ""} {
        set result [dict create \
            contents [dict create \
                kind "markdown" \
                value $hover_info \
            ] \
        ]
    } else {
        set result null
    }

    send_response $id $result
}

# ============================================================================
# Main Request Dispatcher
# ============================================================================

proc handle_request {request} {
    if {[catch {
        set parsed [json::json2dict $request]
    } err]} {
        log_debug "JSON parse error: $err"
        return
    }

    if {![dict exists $parsed method]} {
        log_debug "No method in request"
        return
    }

    set method [dict get $parsed method]
    set params [dict exists $parsed params] ? [dict get $parsed params] : {}

    # Handle notifications (no id)
    if {![dict exists $parsed id]} {
        switch $method {
            "initialized" {
                handle_initialized $params
            }
            "exit" {
                handle_exit $params
            }
            "textDocument/didOpen" -
            "textDocument/didChange" -
            "textDocument/didSave" -
            "textDocument/didClose" {
                # We don't need to do anything special for these notifications
                # in this simple implementation
            }
            default {
                log_debug "Unknown notification: $method"
            }
        }
        return
    }

    # Handle requests (have id)
    set id [dict get $parsed id]

    switch $method {
        "initialize" {
            handle_initialize $id $params
        }
        "shutdown" {
            handle_shutdown $id $params
        }
        "textDocument/completion" {
            handle_completion $id $params
        }
        "textDocument/hover" {
            handle_hover $id $params
        }
        default {
            send_error_response $id -32601 "Method not found: $method"
        }
    }
}

# ============================================================================
# Main Server Loop
# ============================================================================

proc main {} {
    # Configure stdin/stdout for binary mode
    fconfigure stdin -translation binary -buffering none
    fconfigure stdout -translation binary -buffering none

    log_debug "TCL Language Server starting..."

    while {![eof stdin]} {
        set message [read_message]
        if {$message eq ""} {
            continue
        }

        if {[catch {
            handle_request $message
        } err]} {
            log_debug "Error handling request: $err"
        }
    }

    log_debug "TCL Language Server exiting..."
}

# ============================================================================
# Entry Point
# ============================================================================

if {[info script] eq $argv0} {
    main
}
