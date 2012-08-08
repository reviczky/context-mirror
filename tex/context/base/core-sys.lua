if not modules then modules = { } end modules ['core-sys'] = {
    version   = 1.001,
    comment   = "companion to core-sys.mkiv",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

local lower, format = string.lower, string.format
local suffix, basename, removesuffix = file.suffix, file.basename, file.removesuffix

local environment = environment

function commands.updatefilenames(inputfilename,outputfilename)
    environment.inputfilename     = inputfilename or ""
    environment.outputfilename    = outputfilename or ""
    environment.jobfilename       = inputfilename or tex.jobname or ""
    environment.jobfilesuffix     = lower(suffix(environment.jobfilename))
    environment.inputfilebarename = removesuffix(basename(inputfilename))
    environment.inputfilesuffix   = lower(suffix(inputfilename))
end

statistics.register("result saved in file", function()
    -- suffix will be fetched from backend
    return format( "%s.%s", environment.outputfilename, (tex.pdfoutput>0 and "pdf") or "dvi")
end)
