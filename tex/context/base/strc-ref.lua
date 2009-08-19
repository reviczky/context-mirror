if not modules then modules = { } end modules ['strc-ref'] = {
    version   = 1.001,
    comment   = "companion to strc-ref.tex",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

local format, find, gmatch, match = string.format, string.find, string.gmatch, string.match
local texsprint, texwrite, texcount = tex.sprint, tex.write, tex.count

local trace_referencing = false  trackers.register("structure.referencing", function(v) trace_referencing = v end)

local ctxcatcodes = tex.ctxcatcodes
local variables   = interfaces.variables
local constants   = interfaces.constants

-- beware, this is a first step in the rewrite (just getting rid of
-- the tuo file); later all access and parsing will also move to lua

jobreferences           = jobreferences or { }
jobreferences.tobesaved = jobreferences.tobesaved or { }
jobreferences.collected = jobreferences.collected or { }
jobreferences.documents = jobreferences.documents or { }
jobreferences.defined   = jobreferences.defined   or { } -- indirect ones
jobreferences.derived   = jobreferences.derived   or { } -- taken from lists
jobreferences.specials  = jobreferences.specials  or { } -- system references
jobreferences.runners   = jobreferences.runners   or { }
jobreferences.internals = jobreferences.internals or { }

storage.register("jobreferences/defined", jobreferences.defined, "jobreferences.defined")

local tobesaved, collected = jobreferences.tobesaved, jobreferences.collected
local defined, derived, specials, runners = jobreferences.defined, jobreferences.derived, jobreferences.specials, jobreferences.runners

local currentreference = nil

jobreferences.initializers = jobreferences.initializers or { }

function jobreferences.registerinitializer(func) -- we could use a token register instead
    jobreferences.initializers[#jobreferences.initializers+1] = func
end

local function initializer()
    tobesaved, collected = jobreferences.tobesaved, jobreferences.collected
    for k,v in ipairs(jobreferences.initializers) do
        v(tobesaved,collected)
    end
end

if job then
    job.register('jobreferences.collected', jobreferences.tobesaved, initializer)
end

-- todo: delay split till later as in destinations we split anyway

function jobreferences.set(kind,prefix,tag,data)
    for ref in gmatch(tag,"[^,]+") do
        local p, r = match(ref,"^(%-):(.-)$")
        if p and r then
            prefix, ref = p, r
        else
            prefix = ""
        end
        if ref ~= "" then
            local pd = tobesaved[prefix]
            if not pd then
                pd = { }
                tobesaved[prefix] = pd
            end
            pd[ref] = data
            texsprint(ctxcatcodes,format("\\dofinish%sreference{%s}{%s}",kind,prefix,ref))
        end
    end
end

function jobreferences.setandgetattribute(kind,prefix,tag,data) -- maybe do internal automatically here
    jobreferences.set(kind,prefix,tag,data)
    texcount.lastdestinationattribute = jobreferences.setinternalreference(prefix,tag) or -0x7FFFFFFF
end

function jobreferences.enhance(prefix,tag,spec)
    local l = tobesaved[prefix][tag]
    if l then
        l.references.realpage = texcount.realpageno
    end
end

-- this reference parser is just an lpeg version of the tex based one

local result = { }

local lparent, rparent, lbrace, rbrace, dcolon, backslash = lpeg.P("("), lpeg.P(")"), lpeg.P("{"), lpeg.P("}"), lpeg.P("::"), lpeg.P("\\")

local reset     = lpeg.P("") / function()  result = { } end
local b_token   = backslash  / function(s) result.has_tex = true return s end

local o_token   = 1 - rparent - rbrace - lparent - lbrace
local a_token   = 1 - rbrace
local s_token   = 1 - lparent - lbrace - lparent - lbrace
local i_token   = 1 - lparent - lbrace
local f_token   = 1 - lparent - lbrace - dcolon

local outer     =         (f_token          )^1  / function (s) result.outer     = s   end
local operation = lpeg.Cs((b_token + o_token)^1) / function (s) result.operation = s   end
local arguments = lpeg.Cs((b_token + a_token)^0) / function (s) result.arguments = s   end
local special   =         (s_token          )^1  / function (s) result.special   = s   end
local inner     =         (i_token          )^1  / function (s) result.inner     = s   end

local outer_reference    = (outer * dcolon)^0

operation = outer_reference * operation -- special case: page(file::1) and file::page(1)

local optional_arguments = (lbrace  * arguments * rbrace)^0
local inner_reference    = inner * optional_arguments
local special_reference  = special * lparent * (operation * optional_arguments + operation^0) * rparent

local scanner = (reset * outer_reference * (special_reference + inner_reference)^-1 * -1) / function() return result end

function jobreferences.analyse(str)
    return scanner:match(str)
end

function jobreferences.split(str)
    return scanner:match(str or "")
end

--~ print(table.serialize(jobreferences.analyse("")))
--~ print(table.serialize(jobreferences.analyse("inner")))
--~ print(table.serialize(jobreferences.analyse("special(operation{argument,argument})")))
--~ print(table.serialize(jobreferences.analyse("special(operation)")))
--~ print(table.serialize(jobreferences.analyse("special()")))
--~ print(table.serialize(jobreferences.analyse("inner{argument}")))
--~ print(table.serialize(jobreferences.analyse("outer::")))
--~ print(table.serialize(jobreferences.analyse("outer::inner")))
--~ print(table.serialize(jobreferences.analyse("outer::special(operation{argument,argument})")))
--~ print(table.serialize(jobreferences.analyse("outer::special(operation)")))
--~ print(table.serialize(jobreferences.analyse("outer::special()")))
--~ print(table.serialize(jobreferences.analyse("outer::inner{argument}")))
--~ print(table.serialize(jobreferences.analyse("special(outer::operation)")))

-- -- -- related to strc-ini.lua -- -- --

jobreferences.resolvers = jobreferences.resolvers or { }

function jobreferences.resolvers.section(var)
    local vi = structure.lists.collected[var.i[2]]
    if vi then
        var.i = vi
        var.r = (vi.references and vi.references.realpage) or 1
    else
        var.i = nil
        var.r = 1
    end
end

jobreferences.resolvers.float       = jobreferences.resolvers.section
jobreferences.resolvers.description = jobreferences.resolvers.section
jobreferences.resolvers.formula     = jobreferences.resolvers.section
jobreferences.resolvers.note        = jobreferences.resolvers.section

function jobreferences.resolvers.reference(var)
    local vi = var.i[2]
    if vi then
        var.i = vi
        var.r = (vi.references and vi.references.realpage) or 1
    else
        var.i = nil
        var.r = 1
    end
end

local function register_from_lists(collected,derived)
    for i=1,#collected do
        local entry = collected[i]
        local m, r = entry.metadata, entry.references
        if m and r then
            local prefix, reference = r.referenceprefix or "", r.reference or ""
            if reference ~= "" then
                local kind, realpage = m.kind, r.realpage
                if kind and realpage then
                    local d = derived[prefix] if not d then d = { } derived[prefix] = d end
--~                     d[reference] = { kind, i }
for s in gmatch(reference,"[^,]+") do
                    d[s] = { kind, i }
end
                end
            end
        end
    end
end

jobreferences.registerinitializer(function() register_from_lists(structure.lists.collected,derived) end)

-- urls

jobreferences.urls      = jobreferences.urls      or { }
jobreferences.urls.data = jobreferences.urls.data or { }

local urls = jobreferences.urls.data

function jobreferences.urls.define(name,url,file,description)
    if name and name ~= "" then
        urls[name] = { url or "", file or "", description or url or file or ""}
    end
end

function jobreferences.urls.get(name,method,space) -- method: none, before, after, both, space: yes/no
    local u = urls[name]
    if u then
        local url, file = u[1], u[2]
        if file and file ~= "" then
            texsprint(ctxcatcodes,url,"/",file)
        else
            texsprint(ctxcatcodes,url)
        end
    end
end

-- files

jobreferences.files      = jobreferences.files      or { }
jobreferences.files.data = jobreferences.files.data or { }

local files = jobreferences.files.data

function jobreferences.files.define(name,file,description)
    if name and name ~= "" then
        files[name] = { file or "", description or file or ""}
    end
end

function jobreferences.files.get(name,method,space) -- method: none, before, after, both, space: yes/no
    local f = files[name]
    if f then
        texsprint(ctxcatcodes,f[1])
    end
end

-- programs

jobreferences.programs      = jobreferences.programs      or { }
jobreferences.programs.data = jobreferences.programs.data or { }

local programs = jobreferences.programs.data

function jobreferences.programs.define(name,file,description)
    if name and name ~= "" then
        programs[name] = { file or "", description or file or ""}
    end
end

function jobreferences.programs.get(name)
    local f = programs[name]
    if f then
        texsprint(ctxcatcodes,f[1])
    end
end

-- shared by urls and files

function jobreferences.whatfrom(name)
    texsprint(ctxcatcodes,(urls[name] and variables.url) or (files[name] and variables.file) or variables.unknown)
end

function jobreferences.from(name,method,space)
    local u = urls[name]
    if u then
        local url, file, description = u[1], u[2], u[3]
        if description ~= "" then
            -- ok
        elseif file and file ~= "" then
            description = url .. "/" .. file
        else
            description = url
        end
        texsprint(ctxcatcodes,description)
    else
        local f = files[name]
        if f then
            local description, file = f[1], f[2]
            if description ~= "" then
                --
            else
                description = file
            end
            texsprint(ctxcatcodes,description)
        end
    end
end

function jobreferences.load(name)
    if name then
        local jdn = jobreferences.documents[name]
        if not jdn then
            jdn = { }
            local fn = files[name]
            if fn then
                jdn.filename = fn[1]
                local data = io.loaddata(file.replacesuffix(fn[1],"tuc")) or ""
                if data ~= "" then
                    -- quick and dirty, assume sane { } usage inside strings
                    local lists = data:match("structure%.lists%.collected=({.-[\n\r]+})[\n\r]")
                    if lists and lists ~= "" then
                        lists = loadstring("return" .. lists)
                        if lists then
                            jdn.lists = lists()
                            jdn.derived = { }
                            register_from_lists(jdn.lists,jdn.derived)
                        else
                            commands.writestatus("error","invalid structure data in %s",filename)
                        end
                    end
                    local references = data:match("jobreferences%.collected=({.-[\n\r]+})[\n\r]")
                    if references and references ~= "" then
                        references = loadstring("return" .. references)
                        if references then
                            jdn.references = references()
                        else
                            commands.writestatus("error","invalid reference data in %s",filename)
                        end
                    end
                end
            end
            jobreferences.documents[name] = jdn
        end
        return jdn
    else
        return nil
    end
end

function jobreferences.define(prefix,reference,list)
    local d = defined[prefix] if not d then d = { } defined[prefix] = d end
    d[reference] = { "defined", list }
end

--~ function jobreferences.registerspecial(name,action,...)
--~     specials[name] = { action, ... }
--~ end

function jobreferences.reset(prefix,reference)
    local d = defined[prefix]
    if d then
        d[reference] = nil
    end
end

-- \primaryreferencefoundaction
-- \secondaryreferencefoundaction
-- \referenceunknownaction

-- t.special t.operation t.arguments t.outer t.inner

local settings_to_array = aux.settings_to_array

local function resolve(prefix,reference,args,set) -- we start with prefix,reference
    texcount.referencehastexstate = 0
    if reference and reference ~= "" then
        set = set or { }
        local r = settings_to_array(reference)
        for i=1,#r do
            local ri = r[i]
            local dp = defined[prefix] or defined[""]
            local d = dp[ri]
            if d then
                resolve(prefix,d[2],nil,set)
            else
                local var = scanner:match(ri)
                if var then
                    var.reference = ri
                    if not var.outer and var.inner then
                        local d = defined[prefix][var.inner] or defined[""][var.inner]
                        if d then
                            resolve(prefix,d[2],var.arguments,set) -- args can be nil
                        else
                            if args then var.arguments = args end
                            set[#set+1] = var
                        end
                    else
                        if args then var.arguments = args end
                        set[#set+1] = var
                    end
                    if var.has_tex then
                        set.has_tex = true
                    end
                else
                --  logs.report("references","funny pattern: %s",ri or "?")
                end
            end
        end
        if set.has_tex then
            texcount.referencehastexstate = 1
        end
        return set
    else
        return { }
    end
end

-- prefix == "" is valid prefix which saves multistep lookup

jobreferences.currentset = nil

local b, e = "\\ctxlua{local jc = jobreferences.currentset;", "}"
local o, a = 'jc[%s].operation=[[%s]];', 'jc[%s].arguments=[[%s]];'

function jobreferences.expandcurrent() -- todo: two booleans: o_has_tex& a_has_tex
    local currentset = jobreferences.currentset
    if currentset and currentset.has_tex then
        local done = false
        for i=1,#currentset do
            local ci = currentset[i]
            local operation = ci.operation
            if operation then
                if find(operation,"\\") then -- if o_has_tex then
                    if not done then
                        texsprint(ctxcatcodes,b)
                        done = true
                    end
                    texsprint(ctxcatcodes,format(o,i,operation))
                end
            end
            local arguments = ci.arguments
            if arguments then
                if find(arguments,"\\") then -- if a_has_tex then
                    if not done then
                        texsprint(ctxcatcodes,b)
                        done = true
                    end
                    texsprint(ctxcatcodes,format(a,i,arguments))
                end
            end
        end
        if done then
            texsprint(ctxcatcodes,e)
        end
    end
end

local function identify(prefix,reference)
    local set = resolve(prefix,reference)
    local bug = false
    for i=1,#set do
        local var = set[i]
        local special, inner, outer, arguments, operation = var.special, var.inner, var.outer, var.arguments, var.operation
        if special then
            local s = specials[special]
            if s then
                if outer then
                    if operation then
                        -- special(outer::operation)
                        var.kind = "special outer with operation"
                    else
                        -- special()
                        var.kind = "special outer"
                    end
                elseif operation then
                    if arguments then
                        -- special(operation{argument,argument})
                        var.kind = "special operation with arguments"
                    else
                        -- special(operation)
                        var.kind = "special operation"
                    end
                else
                    -- special()
                    var.kind = "special"
                end
            else
                var.error = "unknown special"
            end
        elseif outer then
            local e = jobreferences.load(outer)
            if e then
                local f = e.filename
                if f then
                    if inner then
                        local r = e.references
                        if r then
                            r = r[prefix]
                            if r then
                                r = r[inner]
                                if r then
                                    if arguments then
                                        -- outer::inner{argument}
                                        var.kind = "outer with inner with arguments"
                                    else
                                        -- outer::inner
                                        var.kind = "outer with inner"
                                    end
                                    var.i = { "reference", r }
                                    jobreferences.resolvers.reference(var)
                                    var.f = f
                                end
                            end
                        end
                        if not r then
                            r = e.derived
                            if r then
                                r = r[prefix]
                                if r then
                                    r = r[inner]
                                    if r then
                                        -- outer::inner
                                        if arguments then
                                            -- outer::inner{argument}
                                            var.kind = "outer with inner with arguments"
                                        else
                                            -- outer::inner
                                            var.kind = "outer with inner"
                                        end
                                        var.i = r
                                        jobreferences.resolvers[r[1]](var)
                                        var.f = f
                                    end
                                end
                            end
                        end
                        if not r then
                            var.error = "unknown outer"
                        end
                    elseif special then
                        local s = specials[special]
                        if s then
                            if operation then
                                if arguments then
                                    -- outer::special(operation{argument,argument})
                                    var.kind = "outer with special and operation and arguments"
                                else
                                    -- outer::special(operation)
                                    var.kind = "outer with special and operation"
                                end
                            else
                                -- outer::special()
                                var.kind = "outer with special"
                            end
                            var.f = f
                        else
                            var.error = "unknown outer with special"
                        end
                    else
                        -- outer::
                        var.kind = "outer"
                        var.f = f
                    end
                else
                    var.error = "unknown outer"
                end
            else
                var.error = "unknown outer"
            end
        else
            if arguments then
                local s = specials[inner]
                if s then
                    -- inner{argument}
                    var.kind = "special with arguments"
                else
                    var.error = "unknown inner or special"
                end
            else
                -- inner
--~                 local i = tobesaved[prefix]
                local i = collected[prefix]
                i = i and i[inner]
                if i then
                    var.i = { "reference", i }
                    jobreferences.resolvers.reference(var)
                    var.kind = "inner"
                    var.p = prefix
                else
                    i = derived[prefix]
                    i = i and i[inner]
                    if i then
                        var.kind = "inner"
                        var.i = i
                        jobreferences.resolvers[i[1]](var)
                        var.p = prefix
                    else
                        i = collected[prefix]
                        i = i and i[inner]
                        if i then
                            var.kind = "inner"
                            var.i = { "reference", i }
                            jobreferences.resolvers.reference(var)
                            var.p = prefix
                        else
                            local s = specials[inner]
                            if s then
                                var.kind = "special"
                            else
                                i = (collected[""] and collected[""][inner]) or
                                    (derived  [""] and derived  [""][inner]) or
                                    (tobesaved[""] and tobesaved[""][inner])
                                if i then
                                    var.kind = "inner"
                                    var.i = { "reference", i }
                                    jobreferences.resolvers.reference(var)
                                    var.p = ""
                                else
                                    var.error = "unknown inner or special"
                                end
                            end
                        end
                    end
                end
            end
        end
        bug = bug or var.error
        set[i] = var
    end
    jobreferences.currentset = set
    return set, bug
end

jobreferences.identify = identify

function jobreferences.doifelse(prefix,reference,highlight,newwindow,layer)
    local set, bug = identify(prefix,reference)
    local unknown = bug or #set == 0
    if unknown then
        currentreference = nil -- will go away
    else
        set.highlight, set.newwindow,set.layer = highlight, newwindow, layer
        currentreference = set[1]
    end
    -- we can do the expansion here which saves a call
    commands.doifelse(not unknown)
end

function jobreferences.setinternalreference(prefix,tag,internal,view)
    local t = { }
    if tag then
        if prefix and prefix ~= "" then
            prefix = prefix .. ":"
            for ref in gmatch(tag,"[^,]+") do
                t[#t+1] = prefix .. ref
            end
        else
            for ref in gmatch(tag,"[^,]+") do
                t[#t+1] = ref
            end
        end
    end
    if internal then
        t[#t+1] = "aut:" .. internal
    end
    local destination = jobreferences.mark(t,nil,nil,view) -- returns an attribute
    texcount.lastdestinationattribute = destination
    return destination
end

--

jobreferences.filters = jobreferences.filters or { }

local filters  = jobreferences.filters
local helpers  = structure.helpers
local sections = structure.sections

function jobreferences.filter(name) -- number page title ...
    local data = currentreference and currentreference.i
    if data then
        local kind = data.metadata and data.metadata.kind
        if kind then
            local filter = filters[kind] or filters.generic
            filter = filter and (filter[name] or filters.generic[name])
            if filter then
                filter(data)
            elseif trace_referencing then
                logs.report("referencing","no (generic) filter.name for '%s'",name)
            end
        elseif trace_referencing then
            logs.report("referencing","no metadata.kind for '%s'",name)
        end
    elseif trace_referencing then
        logs.report("referencing","no current reference for '%s'",name)
    end
end

filters.generic = { }

function filters.generic.title(data)
    if data then
        local titledata = data.titledata
        if titledata then
            helpers.title(titledata.title or "?",data.metadata)
        end
    end
end

function filters.generic.text(data)
    if data then
        local entries = data.entries
        if entries then
            helpers.title(entries.text or "?",data.metadata)
        end
    end
end

function filters.generic.number(data) -- todo: spec and then no stopper
    if data then
        helpers.prefix(data)
        local numberdata = data.numberdata
        if numberdata then
            sections.typesetnumber(numberdata,"number",numberdata or false)
        end
    end
end

function filters.generic.page(data,prefixspec,pagespec)
    helpers.prefixpage(data,prefixspec,pagespec)
end

filters.text = { }

function filters.text.title(data)
--  texsprint(ctxcatcodes,"[text title]")
    helpers.title(data.entries.text or "?",data.metadata)
end

function filters.text.number(data)
--  texsprint(ctxcatcodes,"[text number]")
    helpers.title(data.entries.text or "?",data.metadata)
end

function filters.text.page(data,prefixspec,pagespec)
    helpers.prefixpage(data,prefixspec,pagespec)
end

filters.section = { }

filters.section.title  = filters.generic.title
filters.section.page   = filters.generic.page

function filters.section.number(data) -- todo: spec and then no stopper
    if data then
        local numberdata = data.numberdata
        if numberdata then
            sections.typesetnumber(numberdata,"number",numberdata or false)
        end
    end
end

--~ filters.float = { }

--~ filters.float.title  = filters.generic.title
--~ filters.float.number = filters.generic.number
--~ filters.float.page   = filters.generic.page

structure.references = structure.references or { }
structure.helpers    = structure.helpers    or { }

local references = structure.references
local helpers    = structure.helpers

function references.sectiontitle(n)
    helpers.sectiontitle(lists.collected[tonumber(n) or 0])
end

function references.sectionnumber(n)
    helpers.sectionnumber(lists.collected[tonumber(n) or 0])
end

function references.sectionpage(n,prefixspec,pagespec)
    helpers.prefixedpage(lists.collected[tonumber(n) or 0],prefixspec,pagespec)
end

-- analyse

jobreferences.testrunners  = jobreferences.testrunners  or { }
jobreferences.testspecials = jobreferences.testspecials or { }

local runners  = jobreferences.testrunners
local specials = jobreferences.testspecials

function jobreferences.analyse(actions)
    actions = actions or jobreferences.currentset
    if not actions then
        actions = { realpage = 0 }
    elseif actions.realpage then
        -- already analysed
    else
        -- we store some analysis data alongside the indexed array
        -- at this moment only the real reference page is analysed
        -- normally such an analysis happens in the backend code
        texcount.referencepagestate = 0
        local nofactions = #actions
        if nofactions > 0 then
            for i=1,nofactions do
                local a = actions[i]
                local what = runners[a.kind]
                if what then
                    what = what(a,actions)
                end
            end
            local realpage, p = texcount.realpageno, tonumber(actions.realpage)
            if not p then
                -- sorry
            elseif p > realpage then
                texcount.referencepagestate = 3
            elseif p < realpage then
                texcount.referencepagestate = 2
            else
                texcount.referencepagestate = 1
            end
        end
    end
    return actions
end


function jobreferences.realpage() -- special case, we always want result
    local cs = jobreferences.analyse()
    texwrite(cs.realpage or 0)
end

--

jobreferences.pages = {
    [variables.firstpage]       = function() return structure.counters.record("realpage")["first"]    end,
    [variables.previouspage]    = function() return structure.counters.record("realpage")["previous"] end,
    [variables.nextpage]        = function() return structure.counters.record("realpage")["next"]     end,
    [variables.lastpage]        = function() return structure.counters.record("realpage")["last"]     end,

    [variables.firstsubpage]    = function() return structure.counters.record("subpage" )["first"]    end,
    [variables.previoussubpage] = function() return structure.counters.record("subpage" )["previous"] end,
    [variables.nextsubpage]     = function() return structure.counters.record("subpage" )["next"]     end,
    [variables.lastsubpage]     = function() return structure.counters.record("subpage" )["last"]     end,

    [variables.forward]         = function() return structure.counters.record("realpage")["forward"]  end,
    [variables.backward]        = function() return structure.counters.record("realpage")["backward"] end,
}

-- maybe some day i will merge this in the backend code with a testmode (so each
-- runner then implements a branch)

runners["inner"] = function(var,actions)
    local r = var.r
    if r then
        actions.realpage = r
    end
end

runners["special"] = function(var,actions)
    local handler = specials[var.special]
    return handler and handler(var,actions)
end

runners["special operation"]                = runners["special"]
runners["special operation with arguments"] = runners["special"]

local pages = jobreferences.pages

function specials.internal(var,actions)
    local v = jobreferences.internals[tonumber(var.operation)]
    local r = v and v.references.realpage
    if r then
        actions.realpage = r
    end
end

specials.i = specials.internal

function specials.page(var,actions)
    local p = pages[var.operation]
    if type(p) == "function" then
        p = p()
    end
    if p then
        actions.realpage = p
    end
end
