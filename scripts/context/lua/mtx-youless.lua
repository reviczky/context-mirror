if not modules then modules = { } end modules ['mtx-youless'] = {
    version   = 1.002,
    comment   = "script tp fetch data from kwk meter polling device",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE",
    license   = "see context related readme files"
}

-- This script can fetch data from a youless device (http://www.youless.nl/) where data
-- is merged into a file. The data concerns energy consumption (current wattage as well
-- as kwh usage). There is an accompanying module to generate graphics.

require("util-jsn")

-- the library variant:

local youless     = { }
utilities.youless = youless

local lpegmatch  = lpeg.match
local formatters = string.formatters

local http = socket.http

-- maybe just a special parser but who cares about speed here

local function fetch(url,what,i)
    local url    = formatters["http://%s/V?%s=%i&f=j"](url,what,i)
    local data   = http.request(url)
    local result = data and utilities.json.tolua(data)
    return result
end

-- "123"  "  1,234"

local tovalue = lpeg.Cs((lpeg.R("09") + lpeg.P(1)/"")^1) / tonumber

-- "2013-11-12T06:40:00"

local totime = (lpeg.C(4) / tonumber) * lpeg.P("-")
             * (lpeg.C(2) / tonumber) * lpeg.P("-")
             * (lpeg.C(2) / tonumber) * lpeg.P("T")
             * (lpeg.C(2) / tonumber) * lpeg.P(":")
             * (lpeg.C(2) / tonumber) * lpeg.P(":")
             * (lpeg.C(2) / tonumber)

local function get(url,what,i,data,average)
    if not data then
        data = { }
    end
    while true do
        local d = fetch(url,what,i)
        if d and next(d) then
            local c_year, c_month, c_day, c_hour, c_minute, c_seconds = lpegmatch(totime,d.tm)
            if c_year and c_seconds then
                local delta = tonumber(d.dt)
                local tnum = os.time { year = c_year, month = c_month, day = c_day, hour = c_hour, minute = c_minute }
                local v = d.val
                for i=1,#v do
                    local newvalue = lpegmatch(tovalue,v[i])
                    if newvalue then
                        local t = tnum + (i-1)*delta
                        local current = os.date("%Y-%m-%dT%H:%M:%S",t)
                        local c_year, c_month, c_day, c_hour, c_minute, c_seconds = lpegmatch(totime,current)
                        if c_year and c_seconds then
                            local years   = data.years      if not years   then years   = { } data.years      = years   end
                            local d_year  = years[c_year]   if not d_year  then d_year  = { } years[c_year]   = d_year  end
                            local months  = d_year.months   if not months  then months  = { } d_year.months   = months  end
                            local d_month = months[c_month] if not d_month then d_month = { } months[c_month] = d_month end
                            local days    = d_month.days    if not days    then days    = { } d_month.days    = days    end
                            local d_day   = days[c_day]     if not d_day   then d_day   = { } days[c_day]     = d_day   end
                            if average then
                                d_day.average  = newvalue
                            else
                                local hours   = d_day.hours     if not hours   then hours   = { } d_day.hours     = hours   end
                                local d_hour  = hours[c_hour]   if not d_hour  then d_hour  = { } hours[c_hour]   = d_hour  end
                                d_hour[c_minute] = newvalue
                            end
                        end
                    end
                end
            end
        else
            return data
        end
        i = i + 1
    end
    return data
end

-- day of month (kwh)
--     url = http://192.168.1.14/V?m=2
--     m = the number of month (jan = 1, feb = 2, ..., dec = 12)

-- hour of day (watt)
--     url = http://192.168.1.14/V?d=1
--     d = the number of days ago (today = 0, yesterday = 1, etc.)

-- 10 minutes (watt)
--     url = http://192.168.1.14/V?w=1
--     w = 1 for the interval now till 8 hours ago.
--     w = 2 for the interval 8 till 16 hours ago.
--     w = 3 for the interval 16 till 24 hours ago.

-- 1 minute (watt)
--     url = http://192.168.1.14/V?h=1
--     h = 1 for the interval now till 30 minutes ago.
--     h = 2 for the interval 30 till 60 minutes ago

function youless.collect(specification)
    if type(specification) ~= "table" then
        return
    end
    local host     = specification.host     or ""
    local data     = specification.data     or { }
    local filename = specification.filename or ""
    local variant  = specification.variant  or "kwh"
    local detail   = specification.detail   or false
    local nobackup = specification.nobackup or false
    if host == "" then
        return
    end
    if name then
        data = table.load(name) or data
    end
    if variant == "kwh" then
        get(host,"m",1,data,true)
    elseif variant == "watt" then
        get(host,"d",0,data,true)
        get(host,"w",1,data)
        if detail then
            get(host,"h",1,data)
        end
    end
    if filename == "" then
        return
    end
    local path = file.dirname(filename)
    local base = file.basename(filename)
    if nobackup then
        -- saved but with checking
        local tempname = file.join(path,"youless.tmp")
        table.save(tempname,data)
        local check = table.load(tempname)
        if type(check) == "table" then
            local keepname = file.replacesuffix(filename,"old")
            os.remove(keepname)
            if not lfs.isfile(keepname) then
                os.rename(filename,keepname)
                os.rename(tempname,filename)
            end
        end
    else
        local keepname = file.join(path,formatters["%s-%s"](os.date("%Y-%m-%d-%H-%M-%S",os.time()),base))
        os.rename(filename,keepname)
        if not lfs.isfile(filename) then
            table.save(filename,data)
        end
    end
    return data
end

-- local data = youless.collect {
--     host     = "192.168.2.50",
--     variant  = "watt",
--     filename = "youless-watt.lua"
-- }

-- inspect(data)

-- local data = youless.collect {
--     host    = "192.168.2.50",
--     variant = "kwh",
--     filename = "youless-kwh.lua"
-- }

-- inspect(data)

-- the script

local helpinfo = [[
<?xml version="1.0"?>
<application>
 <metadata>
  <entry name="name">mtx-youless</entry>
  <entry name="detail">youless Fetcher</entry>
  <entry name="version">1.00</entry>
 </metadata>
 <flags>
  <category name="basic">
   <subcategory>
    <flag name="collect"><short>collect data from device</short></flag>
    <flag name="nobackup"><short>don't backup old datafile</short></flag>
    <flag name="nofile"><short>don't write data to file (for checking)</short></flag>
    <flag name="kwh"><short>summative kwk data</short></flag>
    <flag name="watt"><short>collected watt data</short></flag>
    <flag name="host"><short>ip address of device</short></flag>
   </subcategory>
  </category>
 </flags>
 <examples>
  <category>
   <title>Example</title>
   <subcategory>
    <example><command>mtxrun --script youless --collect --host=192.168.2.50 --kwk</command></example>
    <example><command>mtxrun --script youless --collect --host=192.168.2.50 --watt somefile.lua</command></example>
   </subcategory>
  </category>
 </examples>
</application>
]]

local application = logs.application {
    name     = "mtx-youless",
    banner   = "youless Fetcher",
    helpinfo = helpinfo,
}

local report = application.report

scripts         = scripts         or { }
scripts.youless = scripts.youless or { }

function scripts.youless.collect()
    local host     = environment.arguments.host
    local variant  = environment.arguments.kwh and "kwh" or environment.arguments.watt and "watt"
    local nobackup = environment.arguments.nobackup
    local nofile   = environment.arguments.nofile
    local filename = environment.files[1]
    if not variant then
        report("provide variant --kwh or --watt")
        return
    else
        report("using variant %a",variant)
    end
    if not host then
        host = "192.168.2.50"
        report("using default host %a",host)
    else
        report("using host %a",host)
    end
    if nobackup then
        report("not backing up data file")
    end
    if not filename and not nofile then
        filename = formatters["youless-%s.lua"](variant)
    end
    if filename ~= "" then
        report("using file %a",filename)
    end
    local data = youless.collect {
        filename = filename,
        host     = host,
        variant  = variant,
        nobackup = nobackup,
    }
    if type(data) ~= "table" then
        report("no data collected")
    elseif filename == "" then
        report("data collected but not saved")
    end
end

if environment.argument("collect") then
    scripts.youless.collect()
elseif environment.argument("exporthelp") then
    application.export(environment.argument("exporthelp"),environment.files[1])
else
    application.help()
end
