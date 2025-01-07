# -*- tcl -*-
# Critcl support, absolutely necessary.
package require critcl
# Bail out early if the compile environment is not suitable.
if {![critcl::compiling]} {
    error "Unable to build project, no proper compiler found."
}
# Information for the teapot.txt meta data file put into a generated package.
# Free form strings.
critcl::license {Andreas Kupries} {Under a BSD license}
critcl::summary {The first CriTcl-based package}
critcl::description {
    Expose Tcl C parse functions to Tcl level.
}
critcl::subject tclp {critcl package}
critcl::subject {basic critcl}
# Minimal Tcl version the package should load into.
critcl::tcl 8.6
# Use to activate Tcl memory debugging
#critcl::debug memory
# Use to activate building and linking with symbols (for gdb, etc.)
#critcl::debug symbols
# ## #### ######### ################ #########################
critcl::cproc tclp {Tcl_Interp* interp pstring parser pstring script int {offset 0}} object0 {

    const char* scriptStart = script.s + offset;
    Tcl_Parse parsePtr;
    const char* termPtr;
    int hasCommandData = 0;
    int termPtrUsed = 0;

    int rt = TCL_OK;

    if (!strcmp(parser.s, "command")) {
        Tcl_ParseCommand(interp, scriptStart, script.len, 0, &parsePtr);
        hasCommandData = 1;
    } else if (!strcmp(parser.s, "expr")) {
        Tcl_ParseExpr(interp, scriptStart, script.len, &parsePtr);
    } else if (!strcmp(parser.s, "braces")) {
        Tcl_ParseBraces(interp, scriptStart, script.len, &parsePtr, 0, &termPtr);
        termPtrUsed = 1;
    } else if (!strcmp(parser.s, "quotedString")) {
        Tcl_ParseQuotedString(interp, scriptStart, script.len, &parsePtr, 0, &termPtr);
        termPtrUsed = 1;
    } else if (!strcmp(parser.s, "varName")) {
        Tcl_ParseVarName(interp, scriptStart, script.len, &parsePtr, 0);
    } else {
        Tcl_SetObjResult(interp, Tcl_NewStringObj("Unknown parser", -1));
        return NULL;
    }

    if (rt == TCL_OK) {

        Tcl_Obj* result = Tcl_NewDictObj();

        if (hasCommandData) {
            Tcl_DictObjPut(interp, result,
                           Tcl_NewStringObj("commentStart", -1),
                           Tcl_NewIntObj(parsePtr.commentSize ? parsePtr.commentStart - script.s : 0));
            Tcl_DictObjPut(interp, result,
                           Tcl_NewStringObj("commentSize", -1),
                           Tcl_NewIntObj(parsePtr.commentSize));
            Tcl_DictObjPut(interp, result,
                           Tcl_NewStringObj("commandStart", -1),
                           Tcl_NewIntObj(parsePtr.commandStart - script.s));
            Tcl_DictObjPut(interp, result,
                           Tcl_NewStringObj("commandSize", -1),
                           Tcl_NewIntObj(parsePtr.commandSize));
        }
        Tcl_DictObjPut(interp, result,
                       Tcl_NewStringObj("numWords", -1),
                       Tcl_NewIntObj(parsePtr.numWords));
        Tcl_DictObjPut(interp, result,
                       Tcl_NewStringObj("numTokens", -1),
                       Tcl_NewIntObj(parsePtr.numTokens));
        if (termPtrUsed) {
            Tcl_DictObjPut(interp, result,
                           Tcl_NewStringObj("termStart", -1),
                           Tcl_NewIntObj(termPtr - script.s));
        }

        Tcl_Obj* tokens = Tcl_NewListObj(NULL, 0);

        for(int i = 0; i < parsePtr.numTokens; i++) {

            Tcl_Obj* token = Tcl_NewDictObj();

            if (parsePtr.tokenPtr[i].type & TCL_TOKEN_WORD) {
                Tcl_DictObjPut(interp, token,
                               Tcl_NewStringObj("type", -1),
                               Tcl_NewStringObj("WORD", -1));
            } else if (parsePtr.tokenPtr[i].type & TCL_TOKEN_SIMPLE_WORD) {
                Tcl_DictObjPut(interp, token,
                               Tcl_NewStringObj("type", -1),
                               Tcl_NewStringObj("SIMPLE_WORD", -1));
            } else if (parsePtr.tokenPtr[i].type & TCL_TOKEN_TEXT) {
                Tcl_DictObjPut(interp, token,
                               Tcl_NewStringObj("type", -1),
                               Tcl_NewStringObj("TEXT", -1));
            } else if (parsePtr.tokenPtr[i].type & TCL_TOKEN_BS) {
                Tcl_DictObjPut(interp, token,
                               Tcl_NewStringObj("type", -1),
                               Tcl_NewStringObj("BS", -1));
            } else if (parsePtr.tokenPtr[i].type & TCL_TOKEN_COMMAND) {
                Tcl_DictObjPut(interp, token,
                               Tcl_NewStringObj("type", -1),
                               Tcl_NewStringObj("COMMAND", -1));
            } else if (parsePtr.tokenPtr[i].type & TCL_TOKEN_VARIABLE) {
                Tcl_DictObjPut(interp, token,
                               Tcl_NewStringObj("type", -1),
                               Tcl_NewStringObj("VARIABLE", -1));
            } else if (parsePtr.tokenPtr[i].type & TCL_TOKEN_SUB_EXPR) {
                Tcl_DictObjPut(interp, token,
                               Tcl_NewStringObj("type", -1),
                               Tcl_NewStringObj("SUB_EXPR", -1));
            } else if (parsePtr.tokenPtr[i].type & TCL_TOKEN_OPERATOR) {
                Tcl_DictObjPut(interp, token,
                               Tcl_NewStringObj("type", -1),
                               Tcl_NewStringObj("OPERATOR", -1));
            } else if (parsePtr.tokenPtr[i].type & TCL_TOKEN_EXPAND_WORD) {
                Tcl_DictObjPut(interp, token,
                               Tcl_NewStringObj("type", -1),
                               Tcl_NewStringObj("EXPAND_WORD", -1));
            } else {
                Tcl_DictObjPut(interp, token,
                               Tcl_NewStringObj("type", -1),
                               Tcl_NewStringObj("UNKNOWN", -1));
            }

            Tcl_DictObjPut(interp, token,
                           Tcl_NewStringObj("start", -1),
                           Tcl_NewIntObj(parsePtr.tokenPtr[i].size ? parsePtr.tokenPtr[i].start - script.s : 0));

            Tcl_DictObjPut(interp, token,
                           Tcl_NewStringObj("size", -1),
                           Tcl_NewIntObj(parsePtr.tokenPtr[i].size));

            Tcl_DictObjPut(interp, token,
                           Tcl_NewStringObj("numComponents", -1),
                           Tcl_NewIntObj(parsePtr.tokenPtr[i].numComponents));

            Tcl_ListObjAppendElement(interp, tokens, token);
        }

        Tcl_DictObjPut(interp, result, Tcl_NewStringObj("tokens", -1), tokens);

        Tcl_FreeParse(&parsePtr);

        return result;

    } else {
        Tcl_SetObjResult(interp, Tcl_NewStringObj("Parsing failed", -1));
        return NULL;
    }
}
# ## #### ######### ################ #########################
# Forcing compilation, link, and loading now.
critcl::msg -nonewline { Building ...}
if {![critcl::load]} {
    error "Building and loading the project failed."
}
# Name and version the package. Just like for every kind of Tcl package.
package provide critcl-tclp 1
