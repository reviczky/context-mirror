if not modules then modules = { } end modules ['java-ini'] = {
    version   = 1.001,
    comment   = "companion to java-ini.mkiv",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

local format = string.format
local concat = table.concat
local lpegmatch, P, S, C, Carg, Cc = lpeg.match, lpeg.P, lpeg.S, lpeg.C, lpeg.Carg, lpeg.Cc

local allocate  = utilities.storage.allocate
local settings_to_array = utilities.parsers.settings_to_array
local variables = interfaces.variables

-- todo: don't flush scripts if no JS key

local trace_javascript = false  trackers.register("backends.javascript", function(v) trace_javascript = v end)

local report_javascripts = logs.reporter ("interactions","javascripts")
local status_javascripts = logs.messenger("interactions","javascripts")

interactions.javascripts = interactions.javascripts or { }
local javascripts        = interactions.javascripts

javascripts.codes        = allocate()
javascripts.preambles    = allocate()
javascripts.functions    = allocate()

local codes, preambles, functions = javascripts.codes, javascripts.preambles, javascripts.functions

local preambled = { }

local function storefunction(s,preamble)
    if trace_javascript then
        report_javascripts("found: function '%s'",s)
    end
    functions[s] = preamble
end

local uses     = P("uses")
local used     = P("used")
local left     = P("{")
local right    = P("}")
local space    = S(" \r\n")
local spaces   = space^0
local braced   = left * C((1-right-space)^1) * right
local unbraced = C((1-space)^1)
local name     = spaces * (braced + unbraced) * spaces
local any      = P(1)
local script   = C(any^1)
local funct    = P("function")
local leftp    = P("(")
local rightp   = P(")")
local fname    = spaces * funct * spaces * (C((1-space-left-leftp)^1) * Carg(1) / storefunction) * spaces * leftp

local parsecode      = name * ((uses * name) + Cc("")) * spaces * script
local parsepreamble  = name * ((used * name) + Cc("")) * spaces * script
local parsefunctions = (fname + any)^0

function javascripts.storecode(str)
    local name, uses, script = lpegmatch(parsecode,str)
    if name and name ~= "" then
        codes[name] = { uses, script }
    end
end

function javascripts.storepreamble(str) -- now later
    local name, used, script = lpegmatch(parsepreamble,str)
    if name and name ~= "" and not preambled[name] then
        local n = #preambles + 1
        preambles[n] = { name, used, script }
        preambled[name] = n
        if trace_javascript then
            report_javascripts("stored: preamble '%s', state '%s', order '%s'",name,used,n)
        end
        lpegmatch(parsefunctions,script,1,n)
    end
end

function javascripts.setpreamble(name,script) -- now later
    if name and name ~= "" and not preambled[name] then
        local n = #preambles + 1
        preambles[n] = { name, "now", script }
        preambled[name] = n
        if trace_javascript then
            report_javascripts("adapted: preamble '%s', state '%s', order '%s'",name,"now",n)
        end
        lpegmatch(parsefunctions,script,1,n)
    end
end

function javascripts.addtopreamble(name,script)
    if name and name ~= "" then
        local p = preambled[name]
        if p then
            preambles[p] = { "now", preambles[p] .. " ;\n" .. script }
            if trace_javascript then
                report_javascripts("extended: preamble '%s', state '%s', order '%s'",name,"now",p)
            end
        else
            local n = #preambles + 1
            preambles[n] = { name, "now", script }
            preambled[name] = n
            if trace_javascript then
                report_javascripts("stored: preamble '%s', state '%s', order '%s'",name,"now",n)
            end
            lpegmatch(parsefunctions,script,1,n)
        end
    end
end

function javascripts.usepreamblenow(name) -- now later
    if name and name ~= "" and name ~= variables.reset then -- todo: reset
        local names = settings_to_array(name)
        for i=1,#names do
            local somename = names[i]
            if not preambled[somename] then
                preambles[preambled[somename]][2] = "now"
                if trace_javascript then
                    report_javascripts("used: preamble '%s', state '%s', order '%s'",somename,"now","auto")
                end
            end
        end
    end
end

local splitter = lpeg.tsplitat(lpeg.patterns.commaspacer)

local used, reported = false, { } -- we can cache more

function javascripts.code(name,arguments)
    local c = codes[name]
    if c then
        local u, code = c[1], c[2]
        if u ~= "" then
            local p = preambled[u]
            if p then
                preambles[p][2] = "now"
                if trace_javascript and not reported[name] then
                    reported[name] = true
                    report_javascripts("used: code '%s', preamble '%s'",name,u)
                end
            elseif trace_javascript and not reported[name] then
                reported[name] = true
                report_javascripts("used: code '%s'",name)
            end
        elseif trace_javascript and not reported[name] then
            reported[name] = true
            report_javascripts("used: code '%s'",name)
        end
        used = true
        return code
    end
    local f = functions[name]
    if f then
        used = true
        if trace_javascript and not reported[name] then
            reported[name] = true
            report_javascripts("used: function '%s'",name)
        end
        preambles[f][2] = "now" -- automatically tag preambles that define the function (as later)
        if arguments then
            local args = lpegmatch(splitter,arguments)
            for i=1,#args do -- can be a helper
                args[i] = format("%q",args[i])
            end
            return format("%s(%s)",name,concat(args,","))
        else
            return format("%s()",name)
        end
    end
end

function javascripts.flushpreambles()
    local t = { }
--     if used then -- we want to be able to enforce inclusion
        for i=1,#preambles do
            local preamble = preambles[i]
            if preamble[2] == "now" then
                if trace_javascript then
                    report_javascripts("flushed: preamble '%s'",preamble[1])
                end
                t[#t+1] = { preamble[1], preamble[3] }
            end
        end
--     end
    return t
end

local patterns = { "java-imp-%s.mkiv", "java-imp-%s.tex", "java-%s.mkiv", "java-%s.tex" }

local function action(name,foundname)
    context.startnointerference()
    context.startreadingfile()
    context.input(foundname)
    status_javascripts("loaded: library '%s'",name)
    context.stopreadingfile()
    context.stopnointerference()
end

local function failure(name)
    report_javascripts("unknown: library '%s'",name)
end

function javascripts.usescripts(name)
    if name ~= variables.reset then -- reset is obsolete
        commands.uselibrary {
            name     = name,
            patterns = patterns,
            action   = action,
            failure  = failure,
            onlyonce = true,
        }
    end
end

-- interface

commands.storejavascriptcode     = interactions.javascripts.storecode
commands.storejavascriptpreamble = interactions.javascripts.storepreamble
commands.addtojavascriptpreamble = interactions.javascripts.addtopreamble
commands.usejavascriptpreamble   = interactions.javascripts.usepreamblenow
commands.usejavascriptscripts    = interactions.javascripts.usescripts
