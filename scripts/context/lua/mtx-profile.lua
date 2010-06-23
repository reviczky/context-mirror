if not modules then modules = { } end modules ['mtx-profile'] = {
    version   = 1.000,
    comment   = "companion to mtxrun.lua",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

-- todo: also line number
-- todo: sort runtime as option

local match, format, find = string.match, string.format, string.find

scripts          = scripts or { }
scripts.profiler = scripts.profiler or { }

local timethreshold    = 0
local callthreshold    = 2500
local countthreshold   = 2500

local functiontemplate  = "%12s %03.4f %9i %s"
local calltemplate      = "%9i %s"
local totaltemplate     = "%i internal calls, %i function calls taking %3.4f seconds"
local thresholdtemplate = "thresholds: %i internal calls, %i function calls, %i seconds"

function scripts.profiler.analyse(filename)
    local f = io.open(filename)
    if f then
        local times, counts, calls = { }, { }, { }
        local totalruntime, totalcount, totalcalls = 0, 0, 0
        while true do
            local line = f:read()
            if line then
                local stacklevel, filename, functionname, linenumber, currentline, localtime, totaltime = line:match("^(%d+)\t(.-)\t(.-)\t(.-)\t(.-)\t(.-)\t(.-)")
                if not filename then
                    -- next
                elseif filename == "=[C]" then
                    if not functionname:find("^%(") then
                        calls[functionname] = (calls[functionname] or 0) + 1
                    end
                else
                    local filename = filename:match("^@(.*)$")
                    if filename then
                        local fi = times[filename]
                        if not fi then fi = { } times[filename] = fi end
                        fi[functionname] = (fi[functionname] or 0) + tonumber(localtime)
                        counts[functionname] = (counts[functionname] or 0) + 1
                    end
                end
            else
                break
            end
        end
        f:close()
        print("")
        local loaded = { }
        local sortedtable.sortedkeys(times)
        for i=1,#sorted do
            local filename = sorted[i]
            local functions = times[filename]
            local sorted = table.sortedkeys(functions)
            for i=1,#sorted do
                local functionname = sorted[i]
                local totaltime = functions[functionname]
                local count = counts[functionname]
                totalcount = totalcount + count
                if totaltime > timethreshold or count > countthreshold then
                    totalruntime = totalruntime + totaltime
                    local functionfile, somenumber = functionname:match("^@(.+):(.-)$")
                    if functionfile then
                        local number = tonumber(somenumber)
                        if number then
                            if not loaded[functionfile] then
                                loaded[functionfile] = string.splitlines(io.loaddata(functionfile) or "")
                            end
                            functionname = loaded[functionfile][number] or functionname
                            functionname = functionname:gsub("^%s*","")
                            functionname = functionname:gsub("%s*%-%-.*$","")
                            functionname = number .. ": " .. functionname
                        end
                    end
                    filename = file.basename(filename)
                    print(functiontemplate:format(filename,totaltime,count,functionname))
                end
            end
        end
        print("")
        local sorted = table.sortedkeys(calls)
        for i=1,#sorted do
            local call = sorted[i]
            local n = calls[call]
            totalcalls = totalcalls + n
            if n > callthreshold then
                print(calltemplate:format(n,call))
            end
        end
        print("")
        print(totaltemplate:format(totalcalls,totalcount,totalruntime))
        print("")
        print(thresholdtemplate:format(callthreshold,countthreshold,timethreshold))
    end
end

function scripts.profiler.x_analyse(filename)
    local f = io.open(filename)
    local calls = { }
    local lines = 0
    if f then
        while true do
            local line = f:read()
            if line then
                lines = lines + 1
                local c = match(line,"\\([a-zA-Z%!%?@]+) *%->")
                if c then
                    local cc = calls[c]
                    if not cc then
                        calls[c] = 1
                    else
                        calls[c] = cc + 1
                    end
                end
            else
                break
            end
        end
        f:close()
        local noc = 0
local criterium = 100
        for name, n in next, calls do
            if n > criterium then
                if find(name,"^@@[a-z][a-z]") then
                    -- parameter
                elseif find(name,"^[cvserft]%!") then
                    -- variables and constants
                elseif find(name,"^%?%?[a-z][a-z]$") then
                    -- prefix
                elseif find(name,"^%!%!") then
                    -- reserved
                elseif find(name,"^@.+@$") then
                    -- weird
                else
                    noc = noc + n
                    print(format("%6i: %s",n,name))
                end
            end
        end
        print("")
        print(format("number of lines: %s",lines))
        print(format("number of calls: %s",noc))
        print(format("criterium calls: %s",criterium))
    end
end

--~ scripts.profiler.analyse("t:/manuals/mk/mk-fonts-profile.lua")
--~ scripts.profiler.analyse("t:/manuals/mk/mk-introduction-profile.lua")

logs.extendbanner("ConTeXt MkIV LuaTeX Profiler 1.00")

messages.help = [[
--analyse             analyse lua calls
--trace               analyse tex calls
]]

if environment.argument("analyse") then
    scripts.profiler.analyse(environment.files[1] or "luatex-profile.log")
elseif environment.argument("trace") then
    scripts.profiler.analyse(environment.files[1] or "temp.log")
else
    logs.help(messages.help)
end
