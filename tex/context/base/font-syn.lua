if not modules then modules = { } end modules ['font-syn'] = {
    version   = 1.001,
    comment   = "companion to font-ini.mkiv",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

local next = next
local gsub, lower, match, find, lower, upper = string.gsub, string.lower, string.match, string.find, string.lower, string.upper
local concat, sort, format = table.concat, table.sort, string.format

local trace_names = false  trackers.register("fonts.names", function(v) trace_names = v end)

--[[ldx--
<p>This module implements a name to filename resolver. Names are resolved
using a table that has keys filtered from the font related files.</p>
--ldx]]--

local texsprint = (tex and tex.sprint) or print

fonts = fonts or { }
input = input or { }
texmf = texmf or { }

fonts.names            = fonts.names         or { }
fonts.names.filters    = fonts.names.filters or { }
fonts.names.data       = fonts.names.data    or { }

local names   = fonts.names
local filters = fonts.names.filters

names.version    = 1.014 -- when adapting this, also changed font-dum.lua
names.basename   = "names"
names.saved      = false
names.loaded     = false
names.be_clever  = true
names.enabled    = true
names.autoreload = toboolean(os.env['MTX.FONTS.AUTOLOAD'] or os.env['MTX_FONTS_AUTOLOAD'] or "no")
names.cache      = containers.define("fonts","data",names.version,true)

--[[ldx--
<p>It would make sense to implement the filters in the related modules,
but to keep the overview, we define them here.</p>
--ldx]]--

filters.otf   = fontloader.info
filters.ttf   = fontloader.info
filters.ttc   = fontloader.info
filters.dfont = fontloader.info

function fontloader.fullinfo(...)
    local ff = fontloader.open(...)
    if ff then
        local d = ff and fontloader.to_table(ff)
        d.glyphs, d.subfonts, d.gpos, d.gsub, d.lookups = nil, nil, nil, nil, nil
        fontloader.close(ff)
        return d
    else
        return nil, "error in loading font"
    end
end

filters.otf   = fontloader.fullinfo

function filters.afm(name)
    -- we could parse the afm file as well, and then report an error but
    -- it's not worth the trouble
    local pfbname = resolvers.find_file(file.removesuffix(name)..".pfb","pfb") or ""
    if pfbname == "" then
        pfbname = resolvers.find_file(file.removesuffix(file.basename(name))..".pfb","pfb") or ""
    end
    if pfbname ~= "" then
        local f = io.open(name)
        if f then
            local hash = { }
            for line in f:lines() do
                local key, value = match(line,"^(.+)%s+(.+)%s*$")
                if key and #key > 0 then
                    hash[lower(key)] = value
                end
                if find(line,"StartCharMetrics") then
                    break
                end
            end
            f:close()
            return hash
        end
    end
    return nil, "no matching pfb file"
end

function filters.pfb(name)
    return fontloader.info(name)
end

--[[ldx--
<p>The scanner loops over the filters using the information stored in
the file databases. Watch how we check not only for the names, but also
for combination with the weight of a font.</p>
--ldx]]--

filters.list = {
    "otf", "ttf", "ttc", "dfont", "afm",
}

filters.fixes = { -- can be lpeg
    { "bolita$", "bolditalic", },
    { "ital$", "italic", },
    { "cond$", "condensed", },
    { "book$", "", },
    { "reg$", "regular", },
    { "ita$", "italic", },
    { "bol$", "bold", },
}

names.xml_configuration_file    = "fonts.conf" -- a bit weird format, bonus feature
names.environment_path_variable = "OSFONTDIR"  -- the official way, in minimals etc

filters.paths = { }
filters.names = { }

function names.getpaths(trace)
    local hash, result = { }, { }
    local function collect(t)
        for i=1, #t do
            local v = resolvers.clean_path(t[i])
            v = gsub(v,"/+$","")
            local key = lower(v)
            if not hash[key] then
                hash[key], result[#result+1] = true, v
            end
        end
    end
    local path = names.environment_path_variable or ""
    if path ~= "" then
        collect(resolvers.expanded_path_list(path))
    end
    if xml then
        local confname = names.xml_configuration_file or ""
        if confname ~= "" then
            -- first look in the tex tree
            local name = resolvers.find_file(confname,"other")
            if name == "" then
                -- after all, fontconfig is a unix thing
                name = file.join("/etc",confname)
                if not lfs.isfile(name) then
                    name = "" -- force quit
                end
            end
            if name ~= "" and lfs.isfile(name) then
                if trace then
                    logs.report("fontnames","loading fontconfig file: %s",name)
                end
                local xmldata = xml.load(name)
                -- begin of untested mess
                xml.include(xmldata,"include","",true,function(incname)
                    if not file.is_qualified_path(incname) then
                        local path = file.dirname(name) -- main name
                        if path ~= "" then
                            incname = file.join(path,incname)
                        end
                    end
                    if lfs.isfile(incname) then
                        if trace then
                            logs.report("fontnames","merging included fontconfig file: %s",incname)
                        end
                        return io.loaddata(incname)
                    elseif trace then
                        logs.report("fontnames","ignoring included fontconfig file: %s",incname)
                    end
                end)
                -- end of untested mess
                local fontdirs = xml.collect_texts(xmldata,"dir",true)
                if trace then
                    logs.report("fontnames","%s dirs found in fontconfig",#fontdirs)
                end
                collect(fontdirs)
            end
        end
    end
    function names.getpaths()
        return result
    end
    return result
end

function names.cleanname(name)
    return (gsub(lower(name),"[^%a%d]",""))
end

function names.identify(verbose) -- lsr is for kpse
    names.data = {
        version = names.version,
        mapping = { },
    --  sorted = { },
        fallback_mapping = { },
    --  fallback_sorted = { },
    }
    local done, mapping, fallback_mapping, nofread, nofok = { }, names.data.mapping, names.data.fallback_mapping, 0, 0
    local cleanname = names.cleanname
    local function check(result, filename, suffix, is_sub) -- unlocal this one
        local fontname = result.fullname
        if fontname then
            local n = cleanname(result.fullname)
            if not mapping[n] then
                mapping[n], nofok = { lower(suffix), fontname, filename, is_sub }, nofok + 1
            end
        end
        if result.fontname then
            fontname = result.fontname or fontname
            local n = cleanname(result.fontname)
            if not mapping[n] then
                mapping[n], nofok = { lower(suffix), fontname, filename, is_sub }, nofok + 1
            end
        end
        if result.familyname and result.weight and result.italicangle == 0 then
            local madename = result.familyname .. " " .. result.weight
            fontname = madename or fontname
            local n = cleanname(fontname)
            if not mapping[n] and not fallback_mapping[n] then
                fallback_mapping[n], nofok = { lower(suffix), fontname, filename, is_sub }, nofok + 1
            end
        end
        if result.names then
            for k, v in ipairs(result.names) do
                local lang, names = v.lang, v.names
                if lang == "English (US)" then
                    local family, subfamily, fullnamet = names.family, names.subfamily, names.fullname
                    local preffamilyname, prefmodifiers, weight = names.preffamilyname, names.prefmodifiers, names.weight
                    if preffamilyname then
                        if subfamily then
                            local n = cleanname(preffamilyname .. " " .. subfamily)
                            if not mapping[n] and not fallback_mapping[n] then
                                fallback_mapping[n], nofok = { lower(suffix), fontname, filename, is_sub }, nofok + 1
                            end
                        end
                        -- okay?
                        local n = cleanname(preffamilyname)
                        if not mapping[n] and not fallback_mapping[n] then
                            fallback_mapping[n], nofok = { lower(suffix), fontname, filename, is_sub }, nofok + 1
                        end
                    end
                end
            end
        end
    end
    local trace = verbose or trace_names
    local skip_paths = filters.paths
    local skip_names = filters.names
    local function identify(completename,name,suffix,storedname)
        if not done[name] and io.exists(completename) then
            nofread = nofread + 1
            if #skip_paths > 0 then
                local path = file.dirname(completename)
                for i=1,#skip_paths do
                    if find(path,skip_paths[i]) then
                        if trace then
                            logs.report("fontnames","rejecting path of %s font %s",suffix,completename)
                            logs.push()
                        end
                        return
                    end
                end
            end
            if #skip_names > 0 then
                local base = file.basename(completename)
                for i=1,#skip_paths do
                    if find(base,skip_names[i]) then
                        done[name] = true
                        if trace then
                            logs.report("fontnames","rejecting name of %s font %s",suffix,completename)
                            logs.push()
                        end
                        return
                    end
                end
            end
            if trace_names then
                logs.report("fontnames","identifying %s font %s",suffix,completename)
                logs.push()
            end
            local result, message = filters[lower(suffix)](completename)
            if trace then
                logs.pop()
            end
            if result then
                if not result[1] then
                    check(result,storedname,suffix,false) -- was name
                else
                    for r=1,#result do
                        check(result[r],storedname,suffix,true) -- was name
                    end
                end
                if message and message ~= "" then
                    logs.report("fontnames","warning when identifying %s font %s: %s",suffix,completename,message)
                end
            else
                logs.report("fontnames","error when identifying %s font %s: %s",suffix,completename,message or "unknown")
            end
            done[name] = true
        end
    end
    local totalread, totalok = 0, 0
    local function traverse(what, method)
        for n, suffix in ipairs(filters.list) do
            nofread, nofok  = 0, 0
            local t = os.gettimeofday() -- use elapser
            suffix = lower(suffix)
            logs.report("fontnames", "identifying %s font files with suffix %s",what,suffix)
            method(suffix)
            suffix = upper(suffix)
            logs.report("fontnames", "identifying %s font files with suffix %s",what,suffix)
            method(suffix)
            logs.report("fontnames", "%s %s files identified, %s hash entries added, runtime %0.3f seconds",nofread,what,nofok,os.gettimeofday()-t)
            totalread, totalok = totalread + nofread, totalok + nofok
        end
    end
    local function walk_tree(pathlist,suffix)
        if pathlist then
            for _, path in ipairs(pathlist) do
                path = resolvers.clean_path(path .. "/")
                path = gsub(path,"/+","/")
                local pattern = path .. "**." .. suffix -- ** forces recurse
                logs.report("fontnames", "globbing path %s",pattern)
                local t = dir.glob(pattern)
                for _, completename in pairs(t) do -- ipairs
                    identify(completename,file.basename(completename),suffix,completename)
                end
            end
        end
    end
    traverse("tree", function(suffix) -- TEXTREE only
        resolvers.with_files(".*%." .. suffix .. "$", function(method,root,path,name)
            if method == "file" then
                local completename = root .."/" .. path .. "/" .. name
                identify(completename,name,suffix,name,name)
            end
        end)
    end)
    if texconfig.kpse_init then
        -- we do this only for a stupid names run, not used for context itself,
        -- using the vars is to clumsy so we just stick to a full scan instead
        traverse("lsr", function(suffix) -- all trees
            local pathlist = resolvers.split_path(resolvers.show_path("ls-R") or "")
            walk_tree(pathlist,suffix)
        end)
    else
        traverse("system", function(suffix) -- OSFONTDIR cum suis
            walk_tree(names.getpaths(trace),suffix)
        end)
    end
    local t = { }
    for _, f in ipairs(filters.fixes) do
        local expression, replacement = f[1], f[2]
        for k,v in next, mapping do
            local fix, pos = gsub(k,expression,replacement)
            if pos > 0 and not mapping[fix] then
                t[fix] = v
            end
        end
    end
    local n = 0
    for k,v in next, t do
        mapping[k] = v
        n = n + 1
    end
    local rejected = 0
    for k, v in next, mapping do
        local kind, filename = v[1], v[3]
        if not file.is_qualified_path(filename) and resolvers.find_file(filename,kind) == "" then
            mapping[k] = nil
            rejected = rejected + 1
        end
    end
    if n > 0 then
        logs.report("fontnames", "%s files read, %s normal and %s extra entries added, %s rejected, %s valid",totalread,totalok,n,rejected,totalok+n-rejected)
    end
    names.analyse(mapping)
    names.analyse(fallback_mapping)
    names.checkduplicates(mapping)
    names.checkduplicates(fallback_mapping)
end

function names.is_permitted(name)
    return containers.is_usable(names.cache(), name)
end
function names.write_data(name,data)
    containers.write(names.cache(),name,data)
end
function names.read_data(name)
    return containers.read(names.cache(),name)
end

local sorter = function(a,b) return #a < #b and a < b end

function names.sorted(t)
    local s = table.keys(t or { }) or { }
    sort(s,sorted)
    return s
end

--~ local P, C, Cc = lpeg.P, lpeg.C, lpeg.Cc
--~
--~ local weight   = C(P("demibold") + P("semibold") + P("mediumbold") + P("ultrabold") + P("bold") + P("demi") + P("semi") + P("light") + P("medium") + P("heavy") + P("ultra") + P("black"))
--~ local style    = C(P("regular") + P("italic") + P("oblique") + P("slanted") + P("roman") + P("ital"))
--~ local width    = C(P("condensed") + P("normal") + P("expanded") + P("cond"))
--~ local special  = P("roman")
--~ local reserved = style + weight + width
--~ local any      = (1-reserved)
--~ local name     = C((special + any)^1)
--~ local crap     = any^0
--~ local dummy    = Cc(false)
--~ local normal   = Cc("normal")
--~ local analyser = name * (weight + normal) * crap * (style + normal) * crap * (width + normal) * crap
--~
--~ function names.analyse(mapping)
--~     for k, v in next, mapping do
--~         -- fails on "Romantik" but that's a border case anyway
--~         local name, weight, style, width = analyser:match(k)
--~         v[5], v[6], v[7], v[8] = name or k, weight or "normal", style or "normal", width or "normal"
--~     end
--~ end

local P, C, Cc, Cs, Carg = lpeg.P, lpeg.C, lpeg.Cc, lpeg.Cs, lpeg.Carg

local weight = C(P("demibold") + P("semibold") + P("mediumbold") + P("ultrabold") + P("bold") + P("demi") + P("semi") + P("light") + P("medium") + P("heavy") + P("ultra") + P("black"))
local style  = C(P("regular") + P("italic") + P("oblique") + P("slanted") + P("roman") + P("ital"))
local width  = C(P("condensed") + P("normal") + P("expanded") + P("cond"))
local strip  = P("book") + P("roman")
local any    = P(1)

local t

local analyser = Cs (
    (
        strip  / "" +
        weight / function(s) t[6] = s return "" end +
        style  / function(s) t[7] = s return "" end +
        width  / function(s) t[8] = s return "" end +
        any
    )^0
)

local stripper = Cs (
    (
        strip  / "" +
        any
    )^0
)

function names.analyse(mapping) -- fails on "Romantik" but that's a border case anyway
    for k, v in next, mapping do
        t = v
        t[5] = analyser:match(k) -- somehow Carg fails
        v[5], v[6], v[7], v[8] = t[5] or k, t[6] or "normal", t[7] or "normal", t[8] or "normal"
    end
end

local splitter = lpeg.splitat("-")

function names.splitspec(askedname)
    local name, weight, style, width = splitter:match(stripper:match(askedname) or askedname)
    if trace_names then
        logs.report("fonts","requested name '%s' split in name '%s', weight '%s', style '%s' and width '%s'",askedname,name or '',weight or '',style or '',width or '')
    end
    if not weight or not weight or not width then
        weight, style, width = weight or "normal", style or "normal", width or "normal"
        if trace_names then
            logs.report("fonts","request '%s' normalized to '%s-%s-%s-%s'",askedname,name,weight,style,width)
        end
    end
    return name or askedname, weight, style, width
end

function names.checkduplicates(mapping) -- fails on "Romantik" but that's a border case anyway
    local loaded = { }
    for k, v in next, mapping do
        local hash = format("%s-%s-%s-%s",v[5],v[6],v[7],v[8])
        local h = loaded[hash]
        if h then
            local ok = true
            local fn = v[3]
            for i=1,#h do
                local hn = mapping[h[i]][3]
                if hn == fn then
                    ok = false
                    break
                end
            end
            if ok then
                h[#h+1] = k
            end
        else
            loaded[hash] = { h }
        end
    end
    for k, v in table.sortedpairs(loaded) do
        if #v > 1 then
            for i=1,#v do
                local vi = v[i]
                v[i] = format("%s = %s",vi,mapping[vi][3])
            end
            logs.report("fonts", "double lookup: %s => %s",k,concat(v," | "))
        end
    end
end

function names.load(reload,verbose)
    if not names.loaded then
        if reload then
            if names.is_permitted(names.basename) then
                names.identify(verbose)
                names.write_data(names.basename,names.data)
            else
                logs.report("font table", "unable to access database cache")
            end
            names.saved = true
        else
            names.data = names.read_data(names.basename)
            if not names.saved then
                if table.is_empty(names.data) or table.is_empty(names.data.mapping) then
                    names.load(true)
                end
                names.saved = true
            end
        end
        local data = names.data
    --  names.analyse(data.mapping)
    --  names.analyse(data.fallback_mapping)
        if data then
            data.sorted = names.sorted(data.mapping)
            data.fallback_sorted = names.sorted(data.fallback_mapping)
        else
            logs.report("font table", "accessing the data table failed")
        end
        names.loaded = true
    end
end

function names.list(pattern,reload)
    names.load(reload)
    if names.loaded then
        local t = { }
        local function list_them(mapping,sorted)
            if mapping[pattern] then
                t[pattern] = mapping[pattern]
            else
                for k,v in ipairs(sorted) do
                    if find(v,pattern) then
                        t[v] = mapping[v]
                    end
                end
            end
        end
        local data = names.data
        if data then
            list_them(data.mapping,data.sorted)
            list_them(data.fallback_mapping,data.fallback_sorted)
        end
        return t
    else
        return nil
    end
end

--[[ldx--
<p>The resolver also checks if the cached names are loaded. Being clever
here is for testing purposes only (it deals with names prefixed by an
encoding name).</p>
--ldx]]--

local function found_indeed(mapping,sorted,name)
    local mn = mapping[name]
    if mn then
        return mn[2], mn[3], mn[4]
    end
    if names.be_clever then -- this will become obsolete
        local encoding, tag = match(name,"^(.-)[%-%:](.+)$")
        local mt = mapping[tag]
        if tag and fonts.enc.is_known(encoding) and mt then
            return mt[1], encoding .. "-" .. mt[3], mt[4]
        end
    end
    -- name, type, file
    for k,v in next, mapping do
        if find(k,name) then
            return v[2], v[3], v[4]
        end
    end
    local condensed = gsub(name,"[^%a%d]","")
    local mc = mapping[condensed]
    if mc then
        return mc[2], mc[3], mc[4]
    end
    for k=1,#sorted do
        local v = sorted[k]
        if find(v,condensed) then
            v = mapping[v]
            return v[2], v[3], v[4]
        end
    end
    return nil, nil, nil
end

local function found(name)
    if name and name ~= "" and names.data then
        name = names.cleanname(name)
        local data = names.data
        local fontname, filename, is_sub = found_indeed(data.mapping, data.sorted, name)
        if not fontname or not filename then
            fontname, filename, is_sub = found_indeed(data.fallback_mapping, data.fallback_sorted, name)
        end
        return fontname, filename, is_sub
    else
        return nil, nil, nil
    end
end

local function collect(stage,mapping,sorted,found,done,name,weight,style,width,all)
    if not mapping or not sorted then
        return
    end
strictname = "^".. name
    local f = mapping[name]
    if weight ~= "" then
        if style ~= "" then
            if width ~= "" then
                if trace_names then
                    logs.report("fonts","resolving stage %s, name '%s', weight '%s', style '%s', width '%s'",stage,name,weight,style,width)
                end
                if f and width ~= f[8] and style == f[7] and weight == f[6] then
                    found[#found+1], done[name] = f, true
                    if not all then return end
                end
                for i=1,#sorted do
                    local k = sorted[i]
                    if not done[k] then
                        local v = mapping[k]
                        if v[6] == weight and v[7] == style and v[8] == width and find(v[5],strictname) then
                            found[#found+1], done[k] = v, true
                            if not all then return end
                        end
                    end
                end
            else
                if trace_names then
                    logs.report("fonts","resolving stage %s, name '%s', weight '%s', style '%s'",stage,name,weight,style)
                end
                if f and style == f[7] and weight == f[6] then
                    found[#found+1], done[name] = f, true
                    if not all then return end
                end
                for i=1,#sorted do
                    local k = sorted[i]
                    if not done[k] then
                        local v = mapping[k]
                        if v[6] == weight and v[7] == style and find(v[5],strictname) then
                            found[#found+1], done[k] = v, true
                            if not all then return end
                        end
                    end
                end
            end
        else
            if trace_names then
                logs.report("fonts","resolving stage %s, name '%s', weight '%s'",stage,name,weight)
            end
            if f and weight == f[6] then
                found[#found+1], done[name] = f, true
                if not all then return end
            end
            for i=1,#sorted do
                local k = sorted[i]
                if not done[k] then
                    local v = mapping[k]
                    if v[6] == weight and find(v[5],strictname) then
                        found[#found+1], done[k] = v, true
                        if not all then return end
                    end
                end
            end
        end
    elseif style ~= "" then
        if width ~= "" then
            if trace_names then
                logs.report("fonts","resolving stage %s, name '%s', style '%s', width '%s'",stage,name,style,width)
            end
            if f and style == f[7] and width == f[8] then
                found[#found+1], done[name] = f, true
                if not all then return end
            end
            for i=1,#sorted do
                local k = sorted[i]
                if not done[k] then
                    local v = mapping[k]
                    if v[7] == style and v[8] == width and find(v[5],strictname) then
                        found[#found+1], done[k] = v, true
                        if not all then return end
                    end
                end
            end
        else
            if trace_names then
                logs.report("fonts","resolving stage %s, name '%s', style '%s'",stage,name,style)
            end
            if f and style == f[7] then
                found[#found+1], done[name] = f, true
                if not all then return end
            end
            for i=1,#sorted do
                local k = sorted[i]
                if not done[k] then
                    local v = mapping[k]
                    if v[7] == style and find(v[5],strictname) then
                        found[#found+1], done[k] = v, true
                        if not all then return end
                    end
                end
            end
        end
    elseif width ~= "" then
        if trace_names then
            logs.report("fonts","resolving stage %s, name '%s', width '%s'",stage,name,width)
        end
        if f and width == f[8] then
            found[#found+1], done[name] = f, true
            if not all then return end
        end
        for i=1,#sorted do
            local k = sorted[i]
            if not done[k] then
                local v = mapping[k]
                if v[8] == width and find(v[5],strictname) then
                    found[#found+1], done[k] = v, true
                    if not all then return end
                end
            end
        end
    else
        if trace_names then
            logs.report("fonts","resolving stage %s, name '%s'",stage,name)
        end
        if f then
            found[#found+1], done[name] = f, true
            if not all then return end
        end
        for i=1,#sorted do
            local k = sorted[i]
            if not done[k] then
                local v = mapping[k]
                if find(v[5],strictname) then
                    found[#found+1], done[k] = v, true
                    if not all then return end
                end
            end
        end
    end
end

function heuristic(name,weight,style,width,all) -- todo: fallbacks
    local found, done = { }, { }
    local data = names.data
    local mapping, sorted, fbmapping, fbsorted = data.mapping, data.sorted, data.fallback_mapping, data.fallback_sorted
    weight, style = weight or "", style or ""
    name = names.cleanname(name)
    collect(1,mapping,sorted,found,done,name,weight,style,width,all)
    if #found == 0 then
        collect(2,fbmapping,fbsorted,found,done,name,weight,style,width,all)
    end
    if #found == 0 and width ~= "" then
        width = "normal"
        collect(3,mapping,sorted,found,done,name,weight,style,width,all)
        if #found == 0 then
            collect(4,fbmapping,fbsorted,found,done,name,weight,style,width,all)
        end
    end
    if #found == 0 and weight ~= "" then -- not style
        weight = "normal"
        collect(5,mapping,sorted,found,done,name,weight,style,width,all)
        if #found == 0 then
            collect(6,fbmapping,fbsorted,found,done,name,weight,style,width,all)
        end
    end
    if #found == 0 and style ~= "" then -- not weight
        style = "normal"
        collect(7,mapping,sorted,found,done,name,weight,style,width,all)
        if #found == 0 then
            collect(8,fbmapping,fbsorted,found,done,name,weight,style,width,all)
        end
    end
    local nf = #found
    if trace_names then
        if nf then
            local t = { }
            for i=1,nf do
                t[#t+1] = format("'%s'",found[i][2])
            end
            logs.report("fonts","name '%s' resolved to %s instances: %s",name,nf,concat(t," "))
        else
            logs.report("fonts","name '%s' unresolved",name)
        end
    end
    if all then
        return nf > 0 and found
    elseif nf > 0 then
        local f = found[1]
        return f[2], f[3], f[4]
    else
        return nil, nil, nil
    end
end

local reloaded = false

function names.specification(askedname,weight,style,width)
    if askedname and askedname ~= "" and names.enabled then
        askedname = lower(askedname) -- or cleanname
        names.load()
        local name, filename, is_sub = heuristic(askedname,weight,style,width)
        if not filename and not reloaded and names.autoreload then
            names.loaded = false
            reloaded = true
            io.flush()
            names.load(true)
            name, filename, is_sub = heuristic(askedname,weight,style,width)
            if not filename then
                name, filename, is_sub = found(askedname) -- old method
            end
        end
        return name, filename, is_sub
    end
end

function names.collect(askedname,weight,style,width)
    if askedname and askedname ~= "" and names.enabled then
        askedname = lower(askedname) -- or cleanname
        names.load()
        local list = heuristic(askedname,weight,style,width,true)
        if not list or #list == 0 and not reloaded and names.autoreload then
            names.loaded = false
            reloaded = true
            io.flush()
            names.load(true)
            list = heuristic(askedname,weight,style,width,true)
        end
        return list
    end
end

function names.resolve(askedname, sub)
    local name, filename, is_sub = names.specification(askedname)
    return filename, (is_sub and name) or sub
end

function names.collectspec(askedname)
    return names.collect(names.splitspec(askedname))
end

function names.resolvespec(askedname,sub)
    local name, filename, is_sub = names.specification(names.splitspec(askedname))
    return filename, (is_sub and name) or sub
end

--[[ldx--
<p>Fallbacks, not permanent but a transition thing.</p>
--ldx]]--

names.new_to_old = {
    ["lmroman10-capsregular"]                = "lmromancaps10-oblique",
    ["lmroman10-capsoblique"]                = "lmromancaps10-regular",
    ["lmroman10-demi"]                       = "lmromandemi10-oblique",
    ["lmroman10-demioblique"]                = "lmromandemi10-regular",
    ["lmroman8-oblique"]                     = "lmromanslant8-regular",
    ["lmroman9-oblique"]                     = "lmromanslant9-regular",
    ["lmroman10-oblique"]                    = "lmromanslant10-regular",
    ["lmroman12-oblique"]                    = "lmromanslant12-regular",
    ["lmroman17-oblique"]                    = "lmromanslant17-regular",
    ["lmroman10-boldoblique"]                = "lmromanslant10-bold",
    ["lmroman10-dunhill"]                    = "lmromandunh10-oblique",
    ["lmroman10-dunhilloblique"]             = "lmromandunh10-regular",
    ["lmroman10-unslanted"]                  = "lmromanunsl10-regular",
    ["lmsans10-demicondensed"]               = "lmsansdemicond10-regular",
    ["lmsans10-demicondensedoblique"]        = "lmsansdemicond10-oblique",
    ["lmsansquotation8-bold"]                = "lmsansquot8-bold",
    ["lmsansquotation8-boldoblique"]         = "lmsansquot8-boldoblique",
    ["lmsansquotation8-oblique"]             = "lmsansquot8-oblique",
    ["lmsansquotation8-regular"]             = "lmsansquot8-regular",
    ["lmtypewriter8-regular"]                = "lmmono8-regular",
    ["lmtypewriter9-regular"]                = "lmmono9-regular",
    ["lmtypewriter10-regular"]               = "lmmono10-regular",
    ["lmtypewriter12-regular"]               = "lmmono12-regular",
    ["lmtypewriter10-italic"]                = "lmmono10-italic",
    ["lmtypewriter10-oblique"]               = "lmmonoslant10-regular",
    ["lmtypewriter10-capsoblique"]           = "lmmonocaps10-oblique",
    ["lmtypewriter10-capsregular"]           = "lmmonocaps10-regular",
    ["lmtypewriter10-light"]                 = "lmmonolt10-regular",
    ["lmtypewriter10-lightoblique"]          = "lmmonolt10-oblique",
    ["lmtypewriter10-lightcondensed"]        = "lmmonoltcond10-regular",
    ["lmtypewriter10-lightcondensedoblique"] = "lmmonoltcond10-oblique",
    ["lmtypewriter10-dark"]                  = "lmmonolt10-bold",
    ["lmtypewriter10-darkoblique"]           = "lmmonolt10-boldoblique",
    ["lmtypewritervarwd10-regular"]          = "lmmonoproplt10-regular",
    ["lmtypewritervarwd10-oblique"]          = "lmmonoproplt10-oblique",
    ["lmtypewritervarwd10-light"]            = "lmmonoprop10-regular",
    ["lmtypewritervarwd10-lightoblique"]     = "lmmonoprop10-oblique",
    ["lmtypewritervarwd10-dark"]             = "lmmonoproplt10-bold",
    ["lmtypewritervarwd10-darkoblique"]      = "lmmonoproplt10-boldoblique",
}

names.old_to_new = table.swapped(names.new_to_old)

function names.exists(name)
    local fna, found = names.autoreload, false
    names.autoreload = false
    for k,v in ipairs(filters.list) do
        found = (resolvers.find_file(name,v) or "") ~= ""
        if found then
            break
        end
    end
    found = found or (resolvers.find_file(name,"tfm") or "") ~= ""
    found = found or (names.resolve(name) or "") ~= ""
    names.autoreload = fna
    return found
end
