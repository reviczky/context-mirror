local info = {
    version   = 1.002,
    comment   = "theme for scintilla lpeg lexer for context/metafun",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files",
}

-- context_path = string.split(os.resultof("mtxrun --find-file context.mkiv"))[1] or ""

-- What used to be proper Lua definitions are in 3.42 SciTE properties although
-- integration is still somewhat half. Also, the indexed style specification is
-- now a hash (which indeed makes more sense). However, the question is: am I
-- going to rewrite the style bit? It anyway makes more sense to keep this file
-- somewhat neutral as we no longer need to be compatible. However, we cannot be
-- sure of helpers being present yet when this file is loaded, so we are somewhat
-- crippled. On the other hand, I don't see other schemes being used with the
-- context lexers.

-- The next kludge is no longer needed:
--
-- if GTK then -- WIN32 GTK OSX CURSES
--     font_name = '!' .. font_name
-- end

local font_name = 'Dejavu Sans Mono'
local font_size = '14'

local colors = {
    red       = { '7F', '00', '00' },
    green     = { '00', '7F', '00' },
    blue      = { '00', '00', '7F' },
    cyan      = { '00', '7F', '7F' },
    magenta   = { '7F', '00', '7F' },
    yellow    = { '7F', '7F', '00' },
    orange    = { 'B0', '7F', '00' },
    --
    white     = { 'FF', 'FF', 'FF' },
    light     = { 'CF', 'CF', 'CF' },
    grey      = { '80', '80', '80' },
    dark      = { '4F', '4F', '4F' },
    black     = { '00', '00', '00' },
    --
    selection = { 'F7', 'F7', 'F7' },
    logpanel  = { 'E7', 'E7', 'E7' },
    textpanel = { 'CF', 'CF', 'CF' },
    linepanel = { 'A7', 'A7', 'A7' },
    tippanel  = { '44', '44', '44' },
    --
    right     = { '00', '00', 'FF' },
    wrong     = { 'FF', '00', '00' },
}

local styles = {

    ["whitespace"]   = { },
    ["default"]      = { font = font_name, size = font_size, fore = colors.black, back = colors.textpanel },
    ["number"]       = { fore = colors.cyan },
    ["comment"]      = { fore = colors.yellow },
    ["keyword"]      = { fore = colors.blue, bold = true },
    ["string"]       = { fore = colors.magenta },
 -- ["preproc"]      = { fore = colors.yellow, bold = true },
    ["error"]        = { fore = colors.red },
    ["label"]        = { fore = colors.red, bold = true  },

    ["nothing"]      = { },
    ["class"]        = { fore = colors.black, bold = true },
    ["function"]     = { fore = colors.black, bold = true },
    ["constant"]     = { fore = colors.cyan, bold = true },
    ["operator"]     = { fore = colors.blue },
    ["regex"]        = { fore = colors.magenta },
    ["preprocessor"] = { fore = colors.yellow, bold = true },
    ["tag"]          = { fore = colors.cyan },
    ["type"]         = { fore = colors.blue },
    ["variable"]     = { fore = colors.black },
    ["identifier"]   = { },

    ["linenumber"]   = { back = colors.linepanel },
    ["bracelight"]   = { fore = colors.orange, bold = true },
    ["bracebad"]     = { fore = colors.orange, bold = true },
    ["controlchar"]  = { },
    ["indentguide"]  = { fore = colors.linepanel, back = colors.white },
    ["calltip"]      = { fore = colors.white, back = colors.tippanel },

    ["invisible"]    = { back = colors.orange },
    ["quote"]        = { fore = colors.blue, bold = true },
    ["special"]      = { fore = colors.blue },
    ["extra"]        = { fore = colors.yellow },
    ["embedded"]     = { fore = colors.black, bold = true },
    ["char"]         = { fore = colors.magenta },
    ["reserved"]     = { fore = colors.magenta, bold = true },
    ["definition"]   = { fore = colors.black, bold = true },
    ["okay"]         = { fore = colors.dark },
    ["warning"]      = { fore = colors.orange },
    ["standout"]     = { fore = colors.orange, bold = true },
    ["command"]      = { fore = colors.green, bold = true },
    ["internal"]     = { fore = colors.orange, bold = true },
    ["preamble"]     = { fore = colors.yellow },
    ["grouping"]     = { fore = colors.red  },
    ["primitive"]    = { fore = colors.blue, bold = true },
    ["plain"]        = { fore = colors.dark, bold = true },
    ["user"]         = { fore = colors.green },
    ["data"]         = { fore = colors.cyan, bold = true },

    -- equal to default:

    ["text"]         = { font = font_name, size = font_size, fore = colors.black, back = colors.textpanel },

}

-- I need to read the C++ code and see how I can load the themes directly
-- in which case we can start thinking of tracing.

if lexer and lexer.context and lexer.context.registerstyles then

    lexer.context.registerstyles(styles)

end
