Start lsp.tcl from emacs:

 (with-eval-after-load 'lsp-mode
   (add-to-list 'lsp-language-id-configuration
                '(tcl-mode . "tcl"))
 
   (lsp-register-client
    (make-lsp-client :new-connection (lsp-stdio-connection "/home/josd/Development/src/lsp/lsp.tcl")
                     :activation-fn (lsp-activate-on "tcl")
                     :server-id 'lsptcl)))

Now load a Tcl file and load lsp.
