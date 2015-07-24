if not modules then modules = { } end modules ['font-ots'] = { -- sequences
    version   = 1.001,
    comment   = "companion to font-ini.mkiv",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files",
}

-- This is a version of font-otn.lua adapted to the new font loader code. It
-- is a context version which can contain experimental code, but when we
-- have serious patches we will backport to the font-otn files. There will
-- be a generic variant too.

-- todo: looks like we have a leak somewhere (probably in ligatures)
-- todo: copy attributes to disc

-- we do some disc juggling where we need to keep in mind that the
-- pre, post and replace fields can have prev pointers to a nesting
-- node ... i wonder if that is still needed
--
-- not possible:
--
-- \discretionary {alpha-} {betagammadelta}
--   {\discretionary {alphabeta-} {gammadelta}
--      {\discretionary {alphabetagamma-} {delta}
--         {alphabetagammadelta}}}

--[[ldx--
<p>This module is a bit more split up that I'd like but since we also want to test
with plain <l n='tex'/> it has to be so. This module is part of <l n='context'/>
and discussion about improvements and functionality mostly happens on the
<l n='context'/> mailing list.</p>

<p>The specification of OpenType is kind of vague. Apart from a lack of a proper
free specifications there's also the problem that Microsoft and Adobe
may have their own interpretation of how and in what order to apply features.
In general the Microsoft website has more detailed specifications and is a
better reference. There is also some information in the FontForge help files.</p>

<p>Because there is so much possible, fonts might contain bugs and/or be made to
work with certain rederers. These may evolve over time which may have the side
effect that suddenly fonts behave differently.</p>

<p>After a lot of experiments (mostly by Taco, me and Idris) we're now at yet another
implementation. Of course all errors are mine and of course the code can be
improved. There are quite some optimizations going on here and processing speed
is currently acceptable. Not all functions are implemented yet, often because I
lack the fonts for testing. Many scripts are not yet supported either, but I will
look into them as soon as <l n='context'/> users ask for it.</p>

<p>The specification leaves room for interpretation. In case of doubt the microsoft
implementation is the reference as it is the most complete one. As they deal with
lots of scripts and fonts, Kai and Ivo did a lot of testing of the generic code and
their suggestions help improve the code. I'm aware that not all border cases can be
taken care of, unless we accept excessive runtime, and even then the interference
with other mechanisms (like hyphenation) are not trivial.</p>

<p>Glyphs are indexed not by unicode but in their own way. This is because there is no
relationship with unicode at all, apart from the fact that a font might cover certain
ranges of characters. One character can have multiple shapes. However, at the
<l n='tex'/> end we use unicode so and all extra glyphs are mapped into a private
space. This is needed because we need to access them and <l n='tex'/> has to include
then in the output eventually.</p>

<p>The initial data table is rather close to the open type specification and also not
that different from the one produced by <l n='fontforge'/> but we uses hashes instead.
In <l n='context'/> that table is packed (similar tables are shared) and cached on disk
so that successive runs can use the optimized table (after loading the table is
unpacked). The flattening code used later is a prelude to an even more compact table
format (and as such it keeps evolving).</p>

<p>This module is sparsely documented because it is a moving target. The table format
of the reader changes and we experiment a lot with different methods for supporting
features.</p>

<p>As with the <l n='afm'/> code, we may decide to store more information in the
<l n='otf'/> table.</p>

<p>Incrementing the version number will force a re-cache. We jump the number by one
when there's a fix in the <l n='fontforge'/> library or <l n='lua'/> code that
results in different tables.</p>
--ldx]]--

local type, next, tonumber = type, next, tonumber
local random = math.random
local formatters = string.formatters

local logs, trackers, nodes, attributes = logs, trackers, nodes, attributes

local registertracker   = trackers.register
local registerdirective = directives.register

local fonts = fonts
local otf   = fonts.handlers.otf

local trace_lookups      = false  registertracker("otf.lookups",      function(v) trace_lookups      = v end)
local trace_singles      = false  registertracker("otf.singles",      function(v) trace_singles      = v end)
local trace_multiples    = false  registertracker("otf.multiples",    function(v) trace_multiples    = v end)
local trace_alternatives = false  registertracker("otf.alternatives", function(v) trace_alternatives = v end)
local trace_ligatures    = false  registertracker("otf.ligatures",    function(v) trace_ligatures    = v end)
local trace_contexts     = false  registertracker("otf.contexts",     function(v) trace_contexts     = v end)
local trace_marks        = false  registertracker("otf.marks",        function(v) trace_marks        = v end)
local trace_kerns        = false  registertracker("otf.kerns",        function(v) trace_kerns        = v end)
local trace_cursive      = false  registertracker("otf.cursive",      function(v) trace_cursive      = v end)
local trace_preparing    = false  registertracker("otf.preparing",    function(v) trace_preparing    = v end)
local trace_bugs         = false  registertracker("otf.bugs",         function(v) trace_bugs         = v end)
local trace_details      = false  registertracker("otf.details",      function(v) trace_details      = v end)
local trace_applied      = false  registertracker("otf.applied",      function(v) trace_applied      = v end)
local trace_steps        = false  registertracker("otf.steps",        function(v) trace_steps        = v end)
local trace_skips        = false  registertracker("otf.skips",        function(v) trace_skips        = v end)
local trace_directions   = false  registertracker("otf.directions",   function(v) trace_directions   = v end)

local trace_kernruns     = false  registertracker("otf.kernruns",     function(v) trace_kernruns     = v end)
local trace_discruns     = false  registertracker("otf.discruns",     function(v) trace_discruns     = v end)
local trace_compruns     = false  registertracker("otf.compruns",     function(v) trace_compruns     = v end)

local quit_on_no_replacement = true  -- maybe per font
local check_discretionaries  = true -- "trace"
local zwnjruns               = true

registerdirective("otf.zwnjruns",                 function(v) zwnjruns = v end)
registerdirective("otf.chain.quitonnoreplacement",function(value) quit_on_no_replacement = value end)

local report_direct   = logs.reporter("fonts","otf direct")
local report_subchain = logs.reporter("fonts","otf subchain")
local report_chain    = logs.reporter("fonts","otf chain")
local report_process  = logs.reporter("fonts","otf process")
local report_prepare  = logs.reporter("fonts","otf prepare")
local report_warning  = logs.reporter("fonts","otf warning")
local report_run      = logs.reporter("fonts","otf run")

registertracker("otf.replacements", "otf.singles,otf.multiples,otf.alternatives,otf.ligatures")
registertracker("otf.positions","otf.marks,otf.kerns,otf.cursive")
registertracker("otf.actions","otf.replacements,otf.positions")
registertracker("otf.injections","nodes.injections")

registertracker("*otf.sample","otf.steps,otf.actions,otf.analyzing")

local nuts               = nodes.nuts
local tonode             = nuts.tonode
local tonut              = nuts.tonut

local getfield           = nuts.getfield
local setfield           = nuts.setfield
local getnext            = nuts.getnext
local getprev            = nuts.getprev
local getid              = nuts.getid
local getattr            = nuts.getattr
local setattr            = nuts.setattr
local getprop            = nuts.getprop
local setprop            = nuts.setprop
local getfont            = nuts.getfont
local getsubtype         = nuts.getsubtype
local getchar            = nuts.getchar

local insert_node_before = nuts.insert_before
local insert_node_after  = nuts.insert_after
local delete_node        = nuts.delete
local remove_node        = nuts.remove
local copy_node          = nuts.copy
local copy_node_list     = nuts.copy_list
local find_node_tail     = nuts.tail
local flush_node_list    = nuts.flush_list
local free_node          = nuts.free
local end_of_math        = nuts.end_of_math
local traverse_nodes     = nuts.traverse
local traverse_id        = nuts.traverse_id

local setmetatableindex  = table.setmetatableindex

local zwnj               = 0x200C
local zwj                = 0x200D
local wildcard           = "*"
local default            = "dflt"

local nodecodes          = nodes.nodecodes
local whatcodes          = nodes.whatcodes
local glyphcodes         = nodes.glyphcodes
local disccodes          = nodes.disccodes

local glyph_code         = nodecodes.glyph
local glue_code          = nodecodes.glue
local disc_code          = nodecodes.disc
local whatsit_code       = nodecodes.whatsit
local math_code          = nodecodes.math

local dir_code           = whatcodes.dir
local localpar_code      = whatcodes.localpar

local discretionary_code = disccodes.discretionary
local regular_code       = disccodes.regular
local automatic_code     = disccodes.automatic

local ligature_code      = glyphcodes.ligature

local privateattribute   = attributes.private

-- Something is messed up: we have two mark / ligature indices, one at the injection
-- end and one here ... this is based on KE's patches but there is something fishy
-- there as I'm pretty sure that for husayni we need some connection (as it's much
-- more complex than an average font) but I need proper examples of all cases, not
-- of only some.

local a_state            = privateattribute('state')
local a_cursbase         = privateattribute('cursbase') -- to be checked, probably can go

local injections         = nodes.injections
local setmark            = injections.setmark
local setcursive         = injections.setcursive
local setkern            = injections.setkern
local setpair            = injections.setpair
local resetinjection     = injections.reset
local copyinjection      = injections.copy
local setligaindex       = injections.setligaindex
local getligaindex       = injections.getligaindex

local cursonce           = true

local fonthashes         = fonts.hashes
local fontdata           = fonthashes.identifiers

local otffeatures        = fonts.constructors.newfeatures("otf")
local registerotffeature = otffeatures.register

local onetimemessage     = fonts.loggers.onetimemessage or function() end

otf.defaultnodealternate = "none" -- first last

local handlers           = { }

-- We use a few global variables. The handler can be called nested but this assumes that the
-- same font is used. Nested calls are normally not needed (only for devanagari).

local tfmdata            = false
local characters         = false
local descriptions       = false
local marks              = false
local currentfont        = false
local factor             = 0

-- head is always a whatsit so we can safely assume that head is not changed

-- handlers  .whatever(head,start,     dataset,sequence,kerns,        step,i,injection)
-- chainprocs.whatever(head,start,stop,dataset,sequence,currentlookup,chainindex)

-- we use this for special testing and documentation

local checkstep       = (nodes and nodes.tracers and nodes.tracers.steppers.check)    or function() end
local registerstep    = (nodes and nodes.tracers and nodes.tracers.steppers.register) or function() end
local registermessage = (nodes and nodes.tracers and nodes.tracers.steppers.message)  or function() end

local function logprocess(...)
    if trace_steps then
        registermessage(...)
    end
    report_direct(...)
end

local function logwarning(...)
    report_direct(...)
end

local f_unicode = formatters["%U"]
local f_uniname = formatters["%U (%s)"]
local f_unilist = formatters["% t (% t)"]

local function gref(n) -- currently the same as in font-otb
    if type(n) == "number" then
        local description = descriptions[n]
        local name = description and description.name
        if name then
            return f_uniname(n,name)
        else
            return f_unicode(n)
        end
    elseif n then
        local num, nam = { }, { }
        for i=1,#n do
            local ni = n[i]
            if tonumber(ni) then -- later we will start at 2
                local di = descriptions[ni]
                num[i] = f_unicode(ni)
                nam[i] = di and di.name or "-"
            end
        end
        return f_unilist(num,nam)
    else
        return "<error in node mode tracing>"
    end
end

local function cref(dataset,sequence,index)
    if index then
        return formatters["feature %a, type %a, chain lookup %a, index %a"](dataset[4],sequence.type,sequence.name,index)
    else
        return formatters["feature %a, type %a, chain lookup %a"](dataset[4],sequence.type,sequence.name)
    end
end

local function pref(dataset,sequence)
    return formatters["feature %a, type %a, lookup %a"](dataset[4],sequence.type,sequence.name)
end

local function mref(rlmode)
    if not rlmode or rlmode == 0 then
        return "---"
    elseif rlmode < 0 then
        return "r2l"
    else
        return "l2r"
    end
end

-- We can assume that languages that use marks are not hyphenated. We can also assume
-- that at most one discretionary is present.

-- We do need components in funny kerning mode but maybe I can better reconstruct then
-- as we do have the font components info available; removing components makes the
-- previous code much simpler. Also, later on copying and freeing becomes easier.
-- However, for arabic we need to keep them around for the sake of mark placement
-- and indices.

local function copy_glyph(g) -- next and prev are untouched !
    local components = getfield(g,"components")
    if components then
        setfield(g,"components",nil)
        local n = copy_node(g)
        copyinjection(n,g) -- we need to preserve the lig indices
        setfield(g,"components",components)
        return n
    else
        local n = copy_node(g)
        copyinjection(n,g) -- we need to preserve the lig indices
        return n
    end
end

-- temp here (context)

local function collapse_disc(start,next)
    local replace1 = getfield(start,"replace")
    local replace2 = getfield(next,"replace")
    if replace1 and replace2 then
        local pre2  = getfield(next,"pre")
        local post2 = getfield(next,"post")
        setfield(replace1,"prev",nil)
        if pre2 then
            local pre1 = getfield(start,"pre")
            if pre1 then
                flush_node_list(pre1)
            end
            local pre1  = copy_node_list(replace1)
            local tail1 = find_node_tail(pre1)
            setfield(tail1,"next",pre2)
            setfield(pre2,"prev",tail1)
            setfield(start,"pre",pre1)
            setfield(next,"pre",nil)
        else
            setfield(start,"pre",nil)
        end
        if post2 then
            local post1 = getfield(start,"post")
            if post1 then
                flush_node_list(post1)
            end
            setfield(start,"post",post2)
        else
            setfield(start,"post",nil)
        end
        local tail1 = find_node_tail(replace1)
        setfield(tail1,"next",replace2)
        setfield(replace2,"prev",tail1)
        setfield(start,"replace",replace1)
        setfield(next,"replace",nil)
        --
        local nextnext = getnext(next)
        setfield(nextnext,"prev",start)
        setfield(start,"next",nextnext)
        free_node(next)
    else
        -- maybe remove it
    end
end

-- start is a mark and we need to keep that one

local function markstoligature(head,start,stop,char)
    if start == stop and getchar(start) == char then
        return head, start
    else
        local prev = getprev(start)
        local next = getnext(stop)
        setfield(start,"prev",nil)
        setfield(stop,"next",nil)
        local base = copy_glyph(start)
        if head == start then
            head = base
        end
        resetinjection(base)
        setfield(base,"char",char)
        setfield(base,"subtype",ligature_code)
        setfield(base,"components",start)
        if prev then
            setfield(prev,"next",base)
        end
        if next then
            setfield(next,"prev",base)
        end
        setfield(base,"next",next)
        setfield(base,"prev",prev)
        return head, base
    end
end

-- The next code is somewhat complicated by the fact that some fonts can have ligatures made
-- from ligatures that themselves have marks. This was identified by Kai in for instance
-- arabtype:  KAF LAM SHADDA ALEF FATHA (0x0643 0x0644 0x0651 0x0627 0x064E). This becomes
-- KAF LAM-ALEF with a SHADDA on the first and a FATHA op de second component. In a next
-- iteration this becomes a KAF-LAM-ALEF with a SHADDA on the second and a FATHA on the
-- third component.

local function getcomponentindex(start)
    if getid(start) ~= glyph_code then
        return 0
    elseif getsubtype(start) == ligature_code then
        local i = 0
        local components = getfield(start,"components")
        while components do
            i = i + getcomponentindex(components)
            components = getnext(components)
        end
        return i
    elseif not marks[getchar(start)] then
        return 1
    else
        return 0
    end
end

local a_noligature     = attributes.private("noligature")
local prehyphenchar    = languages and languages.prehyphenchar
local posthyphenchar   = languages and languages.posthyphenchar
----- preexhyphenchar  = languages and languages.preexhyphenchar
----- postexhyphenchar = languages and languages.postexhyphenchar

if prehyphenchar then

    -- okay

elseif context then

    report_warning("no language support") os.exit()

else

    local newlang   = lang.new
    local getpre    = lang.prehyphenchar
    local getpost   = lang.posthyphenchar
 -- local getpreex  = lang.preexhyphenchar
 -- local getpostex = lang.postexhyphenchar

    prehyphenchar    = function(l) local l = newlang(l) return l and getpre   (l) or -1 end
    posthyphenchar   = function(l) local l = newlang(l) return l and getpost  (l) or -1 end
 -- preexhyphenchar  = function(l) local l = newlang(l) return l and getpreex (l) or -1 end
 -- postexhyphenchar = function(l) local l = newlang(l) return l and getpostex(l) or -1 end

end

local function addhyphens(template,pre,post)
    -- inserted by hyphenation algorithm
    local l = getfield(template,"lang")
    local p = prehyphenchar(l)
    if p and p > 0 then
        local c = copy_node(template)
        setfield(c,"char",p)
        if pre then
            local t = find_node_tail(pre)
            setfield(t,"next",c)
            setfield(c,"prev",t)
        else
            pre = c
        end
    end
    local p = posthyphenchar(l)
    if p and p > 0 then
        local c = copy_node(template)
        setfield(c,"char",p)
        if post then
            -- post has a prev nesting node .. alternatively we could
            local prev = getprev(post)
            setfield(c,"next",post)
            setfield(post,"prev",c)
            if prev then
                setfield(prev,"next",c)
                setfield(c,"prev",prev)
            end
        else
            post = c
        end
    end
    return pre, post
end

local function toligature(head,start,stop,char,dataset,sequence,markflag,discfound) -- brr head
    if getattr(start,a_noligature) == 1 then
        -- so we can do: e\noligature{ff}e e\noligature{f}fie (we only look at the first)
        return head, start
    end
    if start == stop and getchar(start) == char then
        resetinjection(start)
        setfield(start,"char",char)
        return head, start
    end
    -- needs testing (side effects):
    local components = getfield(base,"components")
    if components then
        flush_node_list(components)
    end
    --
    local prev = getprev(start)
    local next = getnext(stop)
    local comp = start
    setfield(start,"prev",nil)
    setfield(stop,"next",nil)
    local base = copy_glyph(start)
    if start == head then
        head = base
    end
    resetinjection(base)
    setfield(base,"char",char)
    setfield(base,"subtype",ligature_code)
    setfield(base,"components",comp) -- start can have components .. do we need to flush?
    if prev then
        setfield(prev,"next",base)
    end
    if next then
        setfield(next,"prev",base)
    end
    setfield(base,"next",next)
    setfield(base,"prev",prev)
    if not discfound then
        local deletemarks = markflag ~= "mark"
        local components = start
        local baseindex = 0
        local componentindex = 0
        local head = base
        local current = base
        -- first we loop over the glyphs in start .. stop
        while start do
            local char = getchar(start)
            if not marks[char] then
                baseindex = baseindex + componentindex
                componentindex = getcomponentindex(start)
            elseif not deletemarks then -- quite fishy
                setligaindex(start,baseindex + getligaindex(start,componentindex))
                if trace_marks then
                    logwarning("%s: keep mark %s, gets index %s",pref(dataset,sequence),gref(char),getligaindex(start))
                end
                local n = copy_node(start)
                copyinjection(n,start)
                head, current = insert_node_after(head,current,n) -- unlikely that mark has components
            elseif trace_marks then
                logwarning("%s: delete mark %s",pref(dataset,sequence),gref(char))
            end
            start = getnext(start)
        end
        -- we can have one accent as part of a lookup and another following
     -- local start = components -- was wrong (component scanning was introduced when more complex ligs in devanagari was added)
        local start = getnext(current)
        while start and getid(start) == glyph_code do
            local char = getchar(start)
            if marks[char] then
                setligaindex(start,baseindex + getligaindex(start,componentindex))
                if trace_marks then
                    logwarning("%s: set mark %s, gets index %s",pref(dataset,sequence),gref(char),getligaindex(start))
                end
            else
                break
            end
            start = getnext(start)
        end
    else
        -- discfound ... forget about marks .. probably no scripts that hyphenate and have marks
        local discprev = getfield(discfound,"prev")
        local discnext = getfield(discfound,"next")
        if discprev and discnext then
            local subtype = getsubtype(discfound)
            if subtype == discretionary_code then
                local pre     = getfield(discfound,"pre")
                local post    = getfield(discfound,"post")
                local replace = getfield(discfound,"replace")
                if not replace then -- todo: signal simple hyphen
                    local prev = getfield(base,"prev")
                    local copied = copy_node_list(comp)
                    setfield(discnext,"prev",nil) -- also blocks funny assignments
                    setfield(discprev,"next",nil) -- also blocks funny assignments
                    if pre then
                        setfield(comp,"next",pre)
                        setfield(pre,"prev",comp)
                    end
                    pre = comp
                    if post then
                        local tail = find_node_tail(post)
                        setfield(tail,"next",discnext)
                        setfield(discnext,"prev",tail)
                        setfield(post,"prev",nil)
                    else
                        post = discnext
                    end
                    setfield(prev,"next",discfound)
                    setfield(next,"prev",discfound)
                    setfield(discfound,"next",next)
                    setfield(discfound,"prev",prev)
                    setfield(base,"next",nil)
                    setfield(base,"prev",nil)
                    setfield(base,"components",copied)
                    setfield(discfound,"pre",pre)
                    setfield(discfound,"post",post)
                    setfield(discfound,"replace",base)
                    setfield(discfound,"subtype",discretionary_code)
                    base = prev -- restart
                end
            elseif discretionary_code == regular_code then
             -- local prev   = getfield(base,"prev")
             -- local next   = getfield(base,"next")
                local copied = copy_node_list(comp)
                setfield(discnext,"prev",nil) -- also blocks funny assignments
                setfield(discprev,"next",nil) -- also blocks funny assignments
                local pre, post = addhyphens(comp,comp,discnext,subtype) -- takes from components
                setfield(prev,"next",discfound)
                setfield(next,"prev",discfound)
                setfield(discfound,"next",next)
                setfield(discfound,"prev",prev)
                setfield(base,"next",nil)
                setfield(base,"prev",nil)
                setfield(base,"components",copied)
                setfield(discfound,"pre",pre)
                setfield(discfound,"post",post)
                setfield(discfound,"replace",base)
                setfield(discfound,"subtype",discretionary_code)
                base = next -- or restart
            else
                -- forget about it in generic usage
            end
        end
    end
    return head, base
end

local function multiple_glyphs(head,start,multiple,ignoremarks)
    local nofmultiples = #multiple
    if nofmultiples > 0 then
        resetinjection(start)
        setfield(start,"char",multiple[1])
        if nofmultiples > 1 then
            local sn = getnext(start)
            for k=2,nofmultiples do -- todo: use insert_node
-- untested:
--
-- while ignoremarks and marks[getchar(sn)] then
--     local sn = getnext(sn)
-- end
                local n = copy_node(start) -- ignore components
                resetinjection(n)
                setfield(n,"char",multiple[k])
                setfield(n,"next",sn)
                setfield(n,"prev",start)
                if sn then
                    setfield(sn,"prev",n)
                end
                setfield(start,"next",n)
                start = n
            end
        end
        return head, start, true
    else
        if trace_multiples then
            logprocess("no multiple for %s",gref(getchar(start)))
        end
        return head, start, false
    end
end

local function get_alternative_glyph(start,alternatives,value)
    local n = #alternatives
    if value == "random" then
        local r = random(1,n)
        return alternatives[r], trace_alternatives and formatters["value %a, taking %a"](value,r)
    elseif value == "first" then
        return alternatives[1], trace_alternatives and formatters["value %a, taking %a"](value,1)
    elseif value == "last" then
        return alternatives[n], trace_alternatives and formatters["value %a, taking %a"](value,n)
    else
        value = value == true and 1 or tonumber(value)
        if type(value) ~= "number" then
            return alternatives[1], trace_alternatives and formatters["invalid value %s, taking %a"](value,1)
        elseif value > n then
            local defaultalt = otf.defaultnodealternate
            if defaultalt == "first" then
                return alternatives[n], trace_alternatives and formatters["invalid value %s, taking %a"](value,1)
            elseif defaultalt == "last" then
                return alternatives[1], trace_alternatives and formatters["invalid value %s, taking %a"](value,n)
            else
                return false, trace_alternatives and formatters["invalid value %a, %s"](value,"out of range")
            end
        elseif value == 0 then
            return getchar(start), trace_alternatives and formatters["invalid value %a, %s"](value,"no change")
        elseif value < 1 then
            return alternatives[1], trace_alternatives and formatters["invalid value %a, taking %a"](value,1)
        else
            return alternatives[value], trace_alternatives and formatters["value %a, taking %a"](value,value)
        end
    end
end

-- handlers

function handlers.gsub_single(head,start,dataset,sequence,replacement)
    if trace_singles then
        logprocess("%s: replacing %s by single %s",pref(dataset,sequence),gref(getchar(start)),gref(replacement))
    end
    resetinjection(start)
    setfield(start,"char",replacement)
    return head, start, true
end

function handlers.gsub_alternate(head,start,dataset,sequence,alternative)
    local kind  = dataset[4]
    local what  = dataset[1]
    local value = what == true and tfmdata.shared.features[kind] or what
    local choice, comment = get_alternative_glyph(start,alternative,value)
    if choice then
        if trace_alternatives then
            logprocess("%s: replacing %s by alternative %a to %s, %s",pref(dataset,sequence),gref(getchar(start)),gref(choice),comment)
        end
        resetinjection(start)
        setfield(start,"char",choice)
    else
        if trace_alternatives then
            logwarning("%s: no variant %a for %s, %s",pref(dataset,sequence),value,gref(getchar(start)),comment)
        end
    end
    return head, start, true
end

function handlers.gsub_multiple(head,start,dataset,sequence,multiple)
    if trace_multiples then
        logprocess("%s: replacing %s by multiple %s",pref(dataset,sequence),gref(getchar(start)),gref(multiple))
    end
    return multiple_glyphs(head,start,multiple,sequence.flags[1])
end

function handlers.gsub_ligature(head,start,dataset,sequence,ligature)
    local current   = getnext(start)
    local stop      = nil
    local startchar = getchar(start)
    if marks[startchar] then
        while current do
            local id = getid(current)
            if id == glyph_code and getfont(current) == currentfont and getsubtype(current)<256 then
                local lg = ligature[getchar(current)]
                if lg then
                    stop     = current
                    ligature = lg
                    current  = getnext(current)
                else
                    break
                end
            else
                break
            end
        end
        if stop then
            local lig = ligature.ligature
            if lig then
                if trace_ligatures then
                    local stopchar = getchar(stop)
                    head, start = markstoligature(head,start,stop,lig)
                    logprocess("%s: replacing %s upto %s by ligature %s case 1",pref(dataset,sequence),gref(startchar),gref(stopchar),gref(getchar(start)))
                else
                    head, start = markstoligature(head,start,stop,lig)
                end
                return head, start, true, false
            else
                -- ok, goto next lookup
            end
        end
    else
        local skipmark  = sequence.flags[1]
        local discfound = false
        local lastdisc  = nil
        while current do
            local id = getid(current)
            if id == glyph_code and getsubtype(current)<256 then -- not needed
                if getfont(current) == currentfont then          -- also not needed only when mark
                    local char = getchar(current)
                    if skipmark and marks[char] then
                        current = getnext(current)
                    else -- ligature is a tree
                        local lg = ligature[char] -- can there be multiple in a row? maybe in a bad font
                        if lg then
                            if not discfound and lastdisc then
                                discfound = lastdisc
                                lastdisc  = nil
                            end
                            stop     = current -- needed for fake so outside then
                            ligature = lg
                            current  = getnext(current)
                        else
                            break
                        end
                    end
                else
                    break
                end
            elseif id == disc_code then
                lastdisc = current
                current  = getnext(current)
            else
                break
            end
        end
        local lig = ligature.ligature
        if lig then
            if stop then
                if trace_ligatures then
                    local stopchar = getchar(stop)
                    head, start = toligature(head,start,stop,lig,dataset,sequence,skipmark,discfound)
                    logprocess("%s: replacing %s upto %s by ligature %s case 2",pref(dataset,sequence),gref(startchar),gref(stopchar),gref(lig))
                else
                    head, start = toligature(head,start,stop,lig,dataset,sequence,skipmark,discfound)
                end
            else
                -- weird but happens (in some arabic font)
                resetinjection(start)
                setfield(start,"char",lig)
                if trace_ligatures then
                    logprocess("%s: replacing %s by (no real) ligature %s case 3",pref(dataset,sequence),gref(startchar),gref(lig))
                end
            end
            return head, start, true, discfound
        else
            -- weird but happens, pseudo ligatures ... just the components
        end
    end
    return head, start, false, discfound
end

-- todo: have this one directly (all are pair now)

function handlers.gpos_single(head,start,dataset,sequence,kerns,rlmode,step,i,injection)
    local startchar = getchar(start)
    if step.format == "pair" then
        local dx, dy, w, h = setpair(start,factor,rlmode,sequence.flags[4],kerns,injection)
        if trace_kerns then
            logprocess("%s: shifting single %s by (%p,%p) and correction (%p,%p)",pref(dataset,sequence),gref(startchar),dx,dy,w,h)
        end
    else
        -- needs checking .. maybe no kerns format for single
        local k = setkern(start,factor,rlmode,kerns,injection)
        if trace_kerns then
            logprocess("%s: shifting single %s by %p",pref(dataset,sequence),gref(startchar),k)
        end
    end
    return head, start, false
end

function handlers.gpos_pair(head,start,dataset,sequence,kerns,rlmode,step,i,injection)
    local snext = getnext(start)
    if not snext then
        return head, start, false
    else
        local prev = start
        local done = false
        while snext and getid(snext) == glyph_code and getfont(snext) == currentfont and getsubtype(snext)<256 do
            local nextchar = getchar(snext)
            local krn = kerns[nextchar]
            if not krn and marks[nextchar] then
                prev = snext
                snext = getnext(snext)
            elseif not krn then
                break
            elseif step.format == "pair" then
                local a, b = krn[1], krn[2]
                if a and #a > 0 then
                    local startchar = getchar(start)
                    local x, y, w, h = setpair(start,factor,rlmode,sequence.flags[4],a,injection) -- characters[startchar])
                    if trace_kerns then
                        logprocess("%s: shifting first of pair %s and %s by (%p,%p) and correction (%p,%p)",pref(dataset,sequence),gref(startchar),gref(nextchar),x,y,w,h)
                    end
                end
                if b and #b > 0 then
                    local startchar = getchar(start)
                    local x, y, w, h = setpair(snext,factor,rlmode,sequence.flags[4],b,injection) -- characters[nextchar])
                    if trace_kerns then
                        logprocess("%s: shifting second of pair %s and %s by (%p,%p) and correction (%p,%p)",pref(dataset,sequence),gref(startchar),gref(nextchar),x,y,w,h)
                    end
                end
                done = true
                break
            elseif krn ~= 0 then
                local k = setkern(snext,factor,rlmode,krn,injection)
                if trace_kerns then
                    logprocess("%s: inserting kern %p between %s and %s",pref(dataset,sequence),k,gref(getchar(prev)),gref(nextchar))
                end
                done = true
                break
            end
        end
        return head, start, done
    end
end

--[[ldx--
<p>We get hits on a mark, but we're not sure if the it has to be applied so
we need to explicitly test for basechar, baselig and basemark entries.</p>
--ldx]]--

-- can we share with chains if we have a stop == nil ?

function handlers.gpos_mark2base(head,start,dataset,sequence,markanchors,rlmode)
    local markchar = getchar(start)
    if marks[markchar] then
        local base = getprev(start) -- [glyph] [start=mark]
        if base and getid(base) == glyph_code and getfont(base) == currentfont and getsubtype(base)<256 then
            local basechar = getchar(base)
            if marks[basechar] then
                while true do
                    base = getprev(base)
                    if base and getid(base) == glyph_code and getfont(base) == currentfont and getsubtype(base)<256 then
                        basechar = getchar(base)
                        if not marks[basechar] then
                            break
                        end
                    else
                        if trace_bugs then
                            logwarning("%s: no base for mark %s",pref(dataset,sequence),gref(markchar))
                        end
                        return head, start, false
                    end
                end
            end
            local ba = markanchors[1][basechar]
            if ba then
                local ma = markanchors[2]
                local dx, dy, bound = setmark(start,base,factor,rlmode,ba,ma,characters[basechar])
                if trace_marks then
                    logprocess("%s, anchor %s, bound %s: anchoring mark %s to basechar %s => (%p,%p)",
                        pref(dataset,sequence),anchor,bound,gref(markchar),gref(basechar),dx,dy)
                end
                return head, start, true
            end
        elseif trace_bugs then
            logwarning("%s: prev node is no char",pref(dataset,sequence))
        end
    elseif trace_bugs then
        logwarning("%s: mark %s is no mark",pref(dataset,sequence),gref(markchar))
    end
    return head, start, false
end

-- ONCE CHECK HERE?

function handlers.gpos_mark2ligature(head,start,dataset,sequence,markanchors,rlmode)
    local markchar = getchar(start)
    if marks[markchar] then
        local base = getprev(start) -- [glyph] [optional marks] [start=mark]
        if base and getid(base) == glyph_code and getfont(base) == currentfont and getsubtype(base)<256 then
            local basechar = getchar(base)
            if marks[basechar] then
                while true do
                    base = getprev(base)
                    if base and getid(base) == glyph_code and getfont(base) == currentfont and getsubtype(base)<256 then
                        basechar = getchar(base)
                        if not marks[basechar] then
                            break
                        end
                    else
                        if trace_bugs then
                            logwarning("%s: no base for mark %s",pref(dataset,sequence),gref(markchar))
                        end
                        return head, start, false
                    end
                end
            end
            local ba = markanchors[1][basechar]
            if ba then
                local ma = markanchors[2]
                if ma then
                    local index = getligaindex(start)
                    ba = ba[index]
                    if ba then
                        local dx, dy, bound = setmark(start,base,factor,rlmode,ba,ma,characters[basechar]) -- index
                        if trace_marks then
                            logprocess("%s, anchor %s, index %s, bound %s: anchoring mark %s to baselig %s at index %s => (%p,%p)",
                                pref(dataset,sequence),anchor,index,bound,gref(markchar),gref(basechar),index,dx,dy)
                        end
                        return head, start, true
                    else
                        if trace_bugs then
                            logwarning("%s: no matching anchors for mark %s and baselig %s with index %a",pref(dataset,sequence),gref(markchar),gref(basechar),index)
                        end
                    end
                end
            elseif trace_bugs then
            --  logwarning("%s: char %s is missing in font",pref(dataset,sequence),gref(basechar))
                onetimemessage(currentfont,basechar,"no base anchors",report_fonts)
            end
        elseif trace_bugs then
            logwarning("%s: prev node is no char",pref(dataset,sequence))
        end
    elseif trace_bugs then
        logwarning("%s: mark %s is no mark",pref(dataset,sequence),gref(markchar))
    end
    return head, start, false
end

function handlers.gpos_mark2mark(head,start,dataset,sequence,markanchors,rlmode)
    local markchar = getchar(start)
    if marks[markchar] then
        local base = getprev(start) -- [glyph] [basemark] [start=mark]
        local slc = getligaindex(start)
        if slc then -- a rather messy loop ... needs checking with husayni
            while base do
                local blc = getligaindex(base)
                if blc and blc ~= slc then
                    base = getprev(base)
                else
                    break
                end
            end
        end
        if base and getid(base) == glyph_code and getfont(base) == currentfont and getsubtype(base)<256 then -- subtype test can go
            local basechar = getchar(base)
            local ba = markanchors[1][basechar] -- slot 1 has been made copy of the class hash
            if ba then
                local ma = markanchors[2]
                local dx, dy, bound = setmark(start,base,factor,rlmode,ba,ma,characters[basechar],true)
                if trace_marks then
                    logprocess("%s, anchor %s, bound %s: anchoring mark %s to basemark %s => (%p,%p)",
                        pref(dataset,sequence),anchor,bound,gref(markchar),gref(basechar),dx,dy)
                end
                return head, start, true
            end
        end
    elseif trace_bugs then
        logwarning("%s: mark %s is no mark",pref(dataset,sequence),gref(markchar))
    end
    return head, start, false
end

function handlers.gpos_cursive(head,start,dataset,sequence,exitanchors,rlmode,step,i) -- to be checked
    local alreadydone = cursonce and getprop(start,a_cursbase)
    if not alreadydone then
        local done = false
        local startchar = getchar(start)
        if marks[startchar] then
            if trace_cursive then
                logprocess("%s: ignoring cursive for mark %s",pref(dataset,sequence),gref(startchar))
            end
        else
            local nxt = getnext(start)
            while not done and nxt and getid(nxt) == glyph_code and getfont(nxt) == currentfont and getsubtype(nxt)<256 do
                local nextchar = getchar(nxt)
                if marks[nextchar] then
                    -- should not happen (maybe warning)
                    nxt = getnext(nxt)
                else
                    local exit = exitanchors[3]
                    if exit then
                        local entry = exitanchors[1][nextchar]
                        if entry then
                            entry = entry[2]
                            if entry then
                                local dx, dy, bound = setcursive(start,nxt,factor,rlmode,exit,entry,characters[startchar],characters[nextchar])
                                if trace_cursive then
                                    logprocess("%s: moving %s to %s cursive (%p,%p) using anchor %s and bound %s in %s mode",pref(dataset,sequence),gref(startchar),gref(nextchar),dx,dy,anchor,bound,mref(rlmode))
                                end
                                done = true
                            end
                        end
                    end
                    break
                end
            end
        end
        return head, start, done
    else
        if trace_cursive and trace_details then
            logprocess("%s, cursive %s is already done",pref(dataset,sequence),gref(getchar(start)),alreadydone)
        end
        return head, start, false
    end
end

--[[ldx--
<p>I will implement multiple chain replacements once I run into a font that uses
it. It's not that complex to handle.</p>
--ldx]]--

local chainprocs = { }

local function logprocess(...)
    if trace_steps then
        registermessage(...)
    end
    report_subchain(...)
end

local logwarning = report_subchain

local function logprocess(...)
    if trace_steps then
        registermessage(...)
    end
    report_chain(...)
end

local logwarning = report_chain

-- We could share functions but that would lead to extra function calls with many
-- arguments, redundant tests and confusing messages.

-- The reversesub is a special case, which is why we need to store the replacements
-- in a bit weird way. There is no lookup and the replacement comes from the lookup
-- itself. It is meant mostly for dealing with Urdu.

function chainprocs.reversesub(head,start,stop,dataset,sequence,replacements,rlmode)
    local char        = getchar(start)
    local replacement = replacements[char]
    if replacement then
        if trace_singles then
            logprocess("%s: single reverse replacement of %s by %s",cref(dataset,sequence),gref(char),gref(replacement))
        end
        resetinjection(start)
        setfield(start,"char",replacement)
        return head, start, true
    else
        return head, start, false
    end
end

--[[ldx--
<p>This chain stuff is somewhat tricky since we can have a sequence of actions to be
applied: single, alternate, multiple or ligature where ligature can be an invalid
one in the sense that it will replace multiple by one but not neccessary one that
looks like the combination (i.e. it is the counterpart of multiple then). For
example, the following is valid:</p>

<typing>
<line>xxxabcdexxx [single a->A][multiple b->BCD][ligature cde->E] xxxABCDExxx</line>
</typing>

<p>Therefore we we don't really do the replacement here already unless we have the
single lookup case. The efficiency of the replacements can be improved by deleting
as less as needed but that would also make the code even more messy.</p>
--ldx]]--

-- local function delete_till_stop(head,start,stop,ignoremarks) -- keeps start
--     local n = 1
--     if start == stop then
--         -- done
--     elseif ignoremarks then
--         repeat -- start x x m x x stop => start m
--             local next = getnext(start)
--             if not marks[getchar(next)] then
--                 local components = getfield(next,"components")
--                 if components then -- probably not needed
--                     flush_node_list(components)
--                 end
--                 head = delete_node(head,next)
--             end
--             n = n + 1
--         until next == stop
--     else -- start x x x stop => start
--         repeat
--             local next = getnext(start)
--             local components = getfield(next,"components")
--             if components then -- probably not needed
--                 flush_node_list(components)
--             end
--             head = delete_node(head,next)
--             n = n + 1
--         until next == stop
--     end
--     return head, n
-- end

--[[ldx--
<p>Here we replace start by a single variant.</p>
--ldx]]--

-- To be done (example needed): what if > 1 steps

-- this is messy: do we need this disc checking also in alternaties?

local function reportmoresteps(dataset,sequence)
    logwarning("%s: more than 1 step",cref(dataset,sequence))
end

function chainprocs.gsub_single(head,start,stop,dataset,sequence,currentlookup,chainindex)
    local steps    = currentlookup.steps
    local nofsteps = currentlookup.nofsteps
    if nofsteps > 1 then
        reportmoresteps(dataset,sequence)
    end
    local current = start
    while current do
        if getid(current) == glyph_code then
            local currentchar = getchar(current)
            local replacement = steps[1].coverage[currentchar]
            if not replacement or replacement == "" then
                if trace_bugs then
                    logwarning("%s: no single for %s",cref(dataset,sequence,chainindex),gref(currentchar))
                end
            else
                if trace_singles then
                    logprocess("%s: replacing single %s by %s",cref(dataset,sequence,chainindex),gref(currentchar),gref(replacement))
                end
                resetinjection(current)
                if check_discretionaries then
                    -- some fonts use a chain lookup to replace e.g. an f in a fi ligature
                    -- and there can be a disc node in between ... the next code tries to catch
                    -- this
                    local next = getnext(current)
                    local prev = getprev(current) -- todo: just remember it above
                    local done = false
                    if next then
                        if getid(next) == disc_code then
                            local subtype = getsubtype(next)
                            if subtype == discretionary_code then
                                setfield(next,"prev",prev)
                                setfield(prev,"next",next)
                                setfield(current,"prev",nil)
                                setfield(current,"next",nil)
                                local replace = getfield(next,"replace")
                                local pre     = getfield(next,"pre")
                                local new     = copy_node(current)
                                setfield(new,"char",replacement)
                                if replace then
                                    setfield(new,"next",replace)
                                    setfield(replace,"prev",new)
                                end
                                if pre then
                                    setfield(current,"next",pre)
                                    setfield(pre,"prev",current)
                                end
                                setfield(next,"replace",new) -- also updates tail
                                setfield(next,"pre",current) -- also updates tail
                            end
                            start = next
                            done = true
                            local next = getnext(start)
                            if next and getid(next) == disc_code then
                                collapse_disc(start,next)
                            end
                        end
                    end
                    if not done and prev then
                        if getid(prev) == disc_code then
                            local subtype = getsubtype(prev)
                            if subtype == discretionary_code then
                                setfield(next,"prev",prev)
                                setfield(prev,"next",next)
                                setfield(current,"prev",nil)
                                setfield(current,"next",nil)
                                local replace = getfield(prev,"replace")
                                local post    = getfield(prev,"post")
                                local new     = copy_node(current)
                                setfield(new,"char",replacement)
                                if replace then
                                    local tail = find_node_tail(replace)
                                    setfield(tail,"next",new)
                                    setfield(new,"prev",tail)
                                else
                                    replace = new
                                end
                                if post then
                                    local tail = find_node_tail(post)
                                    setfield(tail,"next",current)
                                    setfield(current,"prev",tail)
                                else
                                    post = current
                                end
                                setfield(prev,"replace",replace) -- also updates tail
                                setfield(prev,"post",post)       -- also updates tail
                                start = prev
                                done = true
                            end
                        end
                    end
                    if not done then
                        setfield(current,"char",replacement)
                    end
                else
                    setfield(current,"char",replacement)
                end
            end
            return head, start, true
        elseif current == stop then
            break
        else
            current = getnext(current)
        end
    end
    return head, start, false
end

--[[ldx--
<p>Here we replace start by a sequence of new glyphs.</p>
--ldx]]--

-- disc?

function chainprocs.gsub_multiple(head,start,stop,dataset,sequence,currentlookup)
    local steps    = currentlookup.steps
    local nofsteps = currentlookup.nofsteps
    if nofsteps > 1 then
        reportmoresteps(dataset,sequence)
    end
    local startchar   = getchar(start)
    local replacement = steps[1].coverage[startchar]
    if not replacement or replacement == "" then
        if trace_bugs then
            logwarning("%s: no multiple for %s",cref(dataset,sequence),gref(startchar))
        end
    else
        if trace_multiples then
            logprocess("%s: replacing %s by multiple characters %s",cref(dataset,sequence),gref(startchar),gref(replacements))
        end
        return multiple_glyphs(head,start,replacement,currentlookup.flags[1]) -- not sequence.flags?
    end
    return head, start, false
end

--[[ldx--
<p>Here we replace start by new glyph. First we delete the rest of the match.</p>
--ldx]]--

-- char_1 mark_1 -> char_x mark_1 (ignore marks)
-- char_1 mark_1 -> char_x

-- to be checked: do we always have just one glyph?
-- we can also have alternates for marks
-- marks come last anyway
-- are there cases where we need to delete the mark

-- maybe we can share them ...

-- disc ?

function chainprocs.gsub_alternate(head,start,stop,dataset,sequence,currentlookup)
    local steps    = currentlookup.steps
    local nofsteps = currentlookup.nofsteps
    if nofsteps > 1 then
        reportmoresteps(dataset,sequence)
    end
    local kind    = dataset[4]
    local what    = dataset[1]
    local value   = what == true and tfmdata.shared.features[kind] or what
    local current = start
    while current do
        if getid(current) == glyph_code then -- is this check needed?
            local currentchar  = getchar(current)
            local alternatives = steps[1].coverage[currentchar]
            if alternatives then
                local choice, comment = get_alternative_glyph(current,alternatives,value)
                if choice then
                    if trace_alternatives then
                        logprocess("%s: replacing %s by alternative %a to %s, %s",cref(dataset,sequence),gref(char),choice,gref(choice),comment)
                    end
                    resetinjection(start)
                    setfield(start,"char",choice)
                else
                    if trace_alternatives then
                        logwarning("%s: no variant %a for %s, %s",cref(dataset,sequence),value,gref(char),comment)
                    end
                end
            end
            return head, start, true
        elseif current == stop then
            break
        else
            current = getnext(current)
        end
    end
    return head, start, false
end

--[[ldx--
<p>When we replace ligatures we use a helper that handles the marks. I might change
this function (move code inline and handle the marks by a separate function). We
assume rather stupid ligatures (no complex disc nodes).</p>
--ldx]]--

function chainprocs.gsub_ligature(head,start,stop,dataset,sequence,currentlookup,chainindex)
    local steps    = currentlookup.steps
    local nofsteps = currentlookup.nofsteps
    if nofsteps > 1 then
        reportmoresteps(dataset,sequence)
    end
    local startchar = getchar(start)
    local ligatures = steps[1].coverage[startchar]
    if not ligatures then
        if trace_bugs then
            logwarning("%s: no ligatures starting with %s",cref(dataset,sequence,chainindex),gref(startchar))
        end
    else
        local current         = getnext(start)
        local discfound       = false
        local last            = stop
        local nofreplacements = 1
        local skipmark        = currentlookup.flags[1] -- sequence.flags?
        while current do
            local id = getid(current)
            if id == disc_code then
                if not discfound then
                    discfound = current
                end
                if current == stop then
                    break -- okay? or before the disc
                else
                    current = getnext(current)
                end
            else
                local schar = getchar(current)
                    if skipmark and marks[schar] then -- marks
                    -- if current == stop then -- maybe add this
                    --     break
                    -- else
                        current = getnext(current)
                    -- end
                else
                    local lg = ligatures[schar]
                    if lg then
                        ligatures       = lg
                        last            = current
                        nofreplacements = nofreplacements + 1
                        if current == stop then
                            break
                        else
                            current = getnext(current)
                        end
                    else
                        break
                    end
                end
            end
        end
        local ligature = ligatures.ligature
        if ligature then
            if chainindex then
                stop = last
            end
            if trace_ligatures then
                if start == stop then
                    logprocess("%s: replacing character %s by ligature %s case 3",cref(dataset,sequence,chainindex),gref(startchar),gref(ligature))
                else
                    logprocess("%s: replacing character %s upto %s by ligature %s case 4",cref(dataset,sequence,chainindex),gref(startchar),gref(getchar(stop)),gref(ligature))
                end
            end
            head, start = toligature(head,start,stop,ligature,dataset,sequence,skipmark,discfound)
            return head, start, true, nofreplacements, discfound
        elseif trace_bugs then
            if start == stop then
                logwarning("%s: replacing character %s by ligature fails",cref(dataset,sequence,chainindex),gref(startchar))
            else
                logwarning("%s: replacing character %s upto %s by ligature fails",cref(dataset,sequence,chainindex),gref(startchar),gref(getchar(stop)))
            end
        end
    end
    return head, start, false, 0, false
end

function chainprocs.gpos_single(head,start,stop,dataset,sequence,currentlookup,rlmode,chainindex)
    local steps    = currentlookup.steps
    local nofsteps = currentlookup.nofsteps
    if nofsteps > 1 then
        reportmoresteps(dataset,sequence)
    end
    local startchar = getchar(start)
    local step      = steps[1]
    local kerns     = step.coverage[startchar]
    if not kerns then
        -- skip
    elseif step.format == "pair" then
        local dx, dy, w, h = setpair(start,factor,rlmode,sequence.flags[4],kerns) -- currentlookup.flags ?
        if trace_kerns then
            logprocess("%s: shifting single %s by (%p,%p) and correction (%p,%p)",cref(dataset,sequence),gref(startchar),dx,dy,w,h)
        end
    else -- needs checking .. maybe no kerns format for single
        local k = setkern(start,factor,rlmode,kerns,injection)
        if trace_kerns then
            logprocess("%s: shifting single %s by %p",cref(dataset,sequence),gref(startchar),k)
        end
    end
    return head, start, false
end

-- when machines become faster i will make a shared function

function chainprocs.gpos_pair(head,start,stop,dataset,sequence,currentlookup,rlmode,chainindex)
    local steps    = currentlookup.steps
    local nofsteps = currentlookup.nofsteps
    if nofsteps > 1 then
        reportmoresteps(dataset,sequence)
    end
    local snext = getnext(start)
    if snext then
        local startchar = getchar(start)
        local step      = steps[1]
        local kerns     = step.coverage[startchar] -- always 1 step
        if kerns then
            local prev   = start
            local done   = false
            while snext and getid(snext) == glyph_code and getfont(snext) == currentfont and getsubtype(snext)<256 do
                local nextchar = getchar(snext)
                local krn = kerns[nextchar]
                if not krn and marks[nextchar] then
                    prev = snext
                    snext = getnext(snext)
                elseif not krn then
                    break
                elseif step.format == "pair" then
                    local a, b = krn[1], krn[2]
                    if a and #a > 0 then
                        local startchar = getchar(start)
                        local x, y, w, h = setpair(start,factor,rlmode,sequence.flags[4],a) -- currentlookups flags?
                        if trace_kerns then
                            logprocess("%s: shifting first of pair %s and %s by (%p,%p) and correction (%p,%p)",cref(dataset,sequence),gref(startchar),gref(nextchar),x,y,w,h)
                        end
                    end
                    if b and #b > 0 then
                        local startchar = getchar(start)
                        local x, y, w, h = setpair(snext,factor,rlmode,sequence.flags[4],b)
                        if trace_kerns then
                            logprocess("%s: shifting second of pair %s and %s by (%p,%p) and correction (%p,%p)",cref(dataset,sequence),gref(startchar),gref(nextchar),x,y,w,h)
                        end
                    end
                    done = true
                    break
                elseif krn ~= 0 then
                    local k = setkern(snext,factor,rlmode,krn)
                    if trace_kerns then
                        logprocess("%s: inserting kern %s between %s and %s",cref(dataset,sequence),k,gref(getchar(prev)),gref(nextchar))
                    end
                    done = true
                    break
                end
            end
            return head, start, done
        end
    end
    return head, start, false
end

function chainprocs.gpos_mark2base(head,start,stop,dataset,sequence,currentlookup,rlmode)
    local steps    = currentlookup.steps
    local nofsteps = currentlookup.nofsteps
    if nofsteps > 1 then
        reportmoresteps(dataset,sequence)
    end
    local markchar = getchar(start)
    if marks[markchar] then
        local markanchors = steps[1].coverage[markchar] -- always 1 step
        if markanchors then
            local base = getprev(start) -- [glyph] [start=mark]
            if base and getid(base) == glyph_code and getfont(base) == currentfont and getsubtype(base)<256 then
                local basechar = getchar(base)
                if marks[basechar] then
                    while true do
                        base = getprev(base)
                        if base and getid(base) == glyph_code and getfont(base) == currentfont and getsubtype(base)<256 then
                            basechar = getchar(base)
                            if not marks[basechar] then
                                break
                            end
                        else
                            if trace_bugs then
                                logwarning("%s: no base for mark %s",pref(dataset,sequence),gref(markchar))
                            end
                            return head, start, false
                        end
                    end
                end
                local ba = markanchors[1][basechar]
                if ba then
                    local ma = markanchors[2]
                    if ma then
                        local dx, dy, bound = setmark(start,base,factor,rlmode,ba,ma,characters[basechar])
                        if trace_marks then
                            logprocess("%s, anchor %s, bound %s: anchoring mark %s to basechar %s => (%p,%p)",
                                cref(dataset,sequence),anchor,bound,gref(markchar),gref(basechar),dx,dy)
                        end
                        return head, start, true
                    end
                end
            elseif trace_bugs then
                logwarning("%s: prev node is no char",cref(dataset,sequence))
            end
        elseif trace_bugs then
            logwarning("%s: mark %s has no anchors",cref(dataset,sequence),gref(markchar))
        end
    elseif trace_bugs then
        logwarning("%s: mark %s is no mark",cref(dataset,sequence),gref(markchar))
    end
    return head, start, false
end

function chainprocs.gpos_mark2ligature(head,start,stop,dataset,sequence,currentlookup,rlmode)
    local steps    = currentlookup.steps
    local nofsteps = currentlookup.nofsteps
    if nofsteps > 1 then
        reportmoresteps(dataset,sequence)
    end
    local markchar = getchar(start)
    if marks[markchar] then
        local markanchors = steps[1].coverage[markchar] -- always 1 step
        if markanchors then
            local base = getprev(start) -- [glyph] [optional marks] [start=mark]
            if base and getid(base) == glyph_code and getfont(base) == currentfont and getsubtype(base)<256 then
                local basechar = getchar(base)
                if marks[basechar] then
                    while true do
                        base = getprev(base)
                        if base and getid(base) == glyph_code and getfont(base) == currentfont and getsubtype(base)<256 then
                            basechar = getchar(base)
                            if not marks[basechar] then
                                break
                            end
                        else
                            if trace_bugs then
                                logwarning("%s: no base for mark %s",cref(dataset,sequence),markchar)
                            end
                            return head, start, false
                        end
                    end
                end
                local ba = markanchors[1][basechar]
                if ba then
                    local ma = markanchors[2]
                    if ma then
                        local index = getligaindex(start)
                        ba = ba[index]
                        if ba then
                            local dx, dy, bound = setmark(start,base,factor,rlmode,ba,ma,characters[basechar])
                            if trace_marks then
                                logprocess("%s, anchor %s, bound %s: anchoring mark %s to baselig %s at index %s => (%p,%p)",
                                    cref(dataset,sequence),anchor,a or bound,gref(markchar),gref(basechar),index,dx,dy)
                            end
                            return head, start, true
                        end
                    end
                end
            elseif trace_bugs then
                logwarning("%s, prev node is no char",cref(dataset,sequence))
            end
        elseif trace_bugs then
            logwarning("%s, mark %s has no anchors",cref(dataset,sequence),gref(markchar))
        end
    elseif trace_bugs then
        logwarning("%s, mark %s is no mark",cref(dataset,sequence),gref(markchar))
    end
    return head, start, false
end

function chainprocs.gpos_mark2mark(head,start,stop,dataset,sequence,currentlookup,rlmode)
    local steps    = currentlookup.steps
    local nofsteps = currentlookup.nofsteps
    if nofsteps > 1 then
        reportmoresteps(dataset,sequence)
    end
    local markchar = getchar(start)
    if marks[markchar] then
        local markanchors = steps[1].coverage[markchar] -- always 1 step
        if markanchors then
            local base = getprev(start) -- [glyph] [basemark] [start=mark]
            local slc = getligaindex(start)
            if slc then -- a rather messy loop ... needs checking with husayni
                while base do
                    local blc = getligaindex(base)
                    if blc and blc ~= slc then
                        base = getprev(base)
                    else
                        break
                    end
                end
            end
            if base and getid(base) == glyph_code and getfont(base) == currentfont and getsubtype(base)<256 then -- subtype test can go
                local basechar = getchar(base)
                local ba = markanchors[1][basechar]
                if ba then
                    local ma = markanchors[2]
                    if ma then
                        local dx, dy, bound = setmark(start,base,factor,rlmode,ba,ma,characters[basechar],true)
                        if trace_marks then
                            logprocess("%s, anchor %s, bound %s: anchoring mark %s to basemark %s => (%p,%p)",
                                cref(dataset,sequence),anchor,bound,gref(markchar),gref(basechar),dx,dy)
                        end
                        return head, start, true
                    end
                end
            elseif trace_bugs then
                logwarning("%s: prev node is no mark",cref(dataset,sequence))
            end
        elseif trace_bugs then
            logwarning("%s: mark %s has no anchors",cref(dataset,sequence),gref(markchar))
        end
    elseif trace_bugs then
        logwarning("%s: mark %s is no mark",cref(dataset,sequence),gref(markchar))
    end
    return head, start, false
end

function chainprocs.gpos_cursive(head,start,stop,dataset,sequence,currentlookup,rlmode)
    local steps    = currentlookup.steps
    local nofsteps = currentlookup.nofsteps
    if nofsteps > 1 then
        reportmoresteps(dataset,sequence)
    end
    local alreadydone = cursonce and getprop(start,a_cursbase) -- also mkmk?
    if not alreadydone then
        local startchar   = getchar(start)
        local exitanchors = steps[1].coverage[startchar] -- always 1 step
        if exitanchors then
            local done = false
            if marks[startchar] then
                if trace_cursive then
                    logprocess("%s: ignoring cursive for mark %s",pref(dataset,sequence),gref(startchar))
                end
            else
                local nxt = getnext(start)
                while not done and nxt and getid(nxt) == glyph_code and getfont(nxt) == currentfont and getsubtype(nxt)<256 do
                    local nextchar = getchar(nxt)
                    if marks[nextchar] then
                        -- should not happen (maybe warning)
                        nxt = getnext(nxt)
                    else
                        local exit = exitanchors[3]
                        if exit then
                            local entry = exitanchors[1][nextchar]
                            if entry then
                                entry = entry[2]
                                if entry then
                                    local dx, dy, bound = setcursive(start,nxt,factor,rlmode,exit,entry,characters[startchar],characters[nextchar])
                                    if trace_cursive then
                                        logprocess("%s: moving %s to %s cursive (%p,%p) using anchor %s and bound %s in %s mode",pref(dataset,sequence),gref(startchar),gref(nextchar),dx,dy,anchor,bound,mref(rlmode))
                                    end
                                    done = true
                                    break
                                end
                            end
                        elseif trace_bugs then
                            onetimemessage(currentfont,startchar,"no entry anchors",report_fonts)
                        end
                        break
                    end
                end
            end
            return head, start, done
        else
            if trace_cursive and trace_details then
                logprocess("%s, cursive %s is already done",pref(dataset,sequence),gref(getchar(start)),alreadydone)
            end
            return head, start, false
        end
    end
    return head, start, false
end

-- what pointer to return, spec says stop
-- to be discussed ... is bidi changer a space?
-- elseif char == zwnj and sequence[n][32] then -- brrr

local function show_skip(dataset,sequence,char,ck,class)
    logwarning("%s: skipping char %s, class %a, rule %a, lookuptype %a",cref(dataset,sequence),gref(char),class,ck[1],ck[8])
end

local function handle_contextchain(head,start,dataset,sequence,contexts,rlmode)
    local flags        = sequence.flags
    local done         = false
    local skipmark     = flags[1]
    local skipligature = flags[2]
    local skipbase     = flags[3]
    local markclass    = sequence.markclass
    local skipped      = false
    for k=1,#contexts do
        local match   = true
        local current = start
        local last    = start
        local ck      = contexts[k]
        local seq     = ck[3]
        local s       = #seq
        -- f..l = mid string
        if s == 1 then
            -- never happens
            match = getid(current) == glyph_code and getfont(current) == currentfont and getsubtype(current)<256 and seq[1][getchar(current)]
        else
            -- maybe we need a better space check (maybe check for glue or category or combination)
            -- we cannot optimize for n=2 because there can be disc nodes
            local f = ck[4]
            local l = ck[5]
            -- current match
            if f == 1 and f == l then -- current only
                -- already a hit -- do we need to check for mark?
             -- match = true
            else -- before/current/after | before/current | current/after
                -- no need to test first hit (to be optimized)
                if f == l then -- new, else last out of sync (f is > 1)
                 -- match = true
                else
                    local n = f + 1
                    last = getnext(last)
                    while n <= l do
                        if last then
                            local id = getid(last)
                            if id == glyph_code then
                                if getfont(last) == currentfont and getsubtype(last)<256 then
                                    local char = getchar(last)
                                    local ccd = descriptions[char]
                                    if ccd then
                                        local class = ccd.class or "base"
                                        if class == skipmark or class == skipligature or class == skipbase or (markclass and class == "mark" and not markclass[char]) then
                                            skipped = true
                                            if trace_skips then
                                                show_skip(dataset,sequence,char,ck,class)
                                            end
                                            last = getnext(last)
                                        elseif seq[n][char] then
                                            if n < l then
                                                last = getnext(last)
                                            end
                                            n = n + 1
                                        else
                                            match = false
                                            break
                                        end
                                    else
                                        match = false
                                        break
                                    end
                                else
                                    match = false
                                    break
                                end
                            elseif id == disc_code then
                                if check_discretionaries then
                                    local replace = getfield(last,"replace")
                                    if replace then
                                        -- so far we never entered this branch
                                        while replace do
                                            if seq[n][getchar(replace)] then
                                                n = n + 1
                                                replace = getnext(replace)
                                                if not replace then
                                                    break
                                                elseif n > l then
                                                 -- match = false
                                                    break
                                                end
                                            else
                                                match = false
                                                break
                                            end
                                        end
                                        if not match then
                                            break
                                        elseif check_discretionaries == "trace" then
                                            report_chain("check disc action in current")
                                        end
                                    else
                                        last = getnext(last) -- no skipping here
                                    end
                                else
                                    last = getnext(last) -- no skipping here
                                end
                            else
                                match = false
                                break
                            end
                        else
                            match = false
                            break
                        end
                    end
                end
            end
            -- before
            if match and f > 1 then
                local prev = getprev(start)
                if prev then
                    local n = f-1
                    while n >= 1 do
                        if prev then
                            local id = getid(prev)
                            if id == glyph_code then
                                if getfont(prev) == currentfont and getsubtype(prev)<256 then -- normal char
                                    local char = getchar(prev)
                                    local ccd = descriptions[char]
                                    if ccd then
                                        local class = ccd.class or "base"
                                        if class == skipmark or class == skipligature or class == skipbase or (markclass and class == "mark" and not markclass[char]) then
                                            skipped = true
                                            if trace_skips then
                                                show_skip(dataset,sequence,char,ck,class)
                                            end
                                        elseif seq[n][char] then
                                            n = n -1
                                        else
                                            match = false
                                            break
                                        end
                                    else
                                        match = false
                                        break
                                    end
                                else
                                    match = false
                                    break
                                end
                            elseif id == disc_code then
                                -- the special case: f i where i becomes dottless i ..
                                if check_discretionaries then
                                    local replace = getfield(prev,"replace")
                                    if replace then
                                        -- we seldom enter this branch (e.g. on brill efficient)
                                        replace = find_node_tail(replace)
                                        local finish = getprev(replace)
                                        while replace do
                                            if seq[n][getchar(replace)] then
                                                n = n - 1
                                                replace = getprev(replace)
                                                if not replace or replace == finish then
                                                    break
                                                elseif n < 1 then
                                                 -- match = false
                                                    break
                                                end
                                            else
                                                match = false
                                                break
                                            end
                                        end
                                        if not match then
                                            break
                                        elseif check_discretionaries == "trace" then
                                            report_chain("check disc action in before")
                                        end
                                    else
                                        -- skip 'm
                                    end
                                else
                                    -- skip 'm
                                end
                            elseif seq[n][32] then
                                n = n -1
                            else
                                match = false
                                break
                            end
                            prev = getprev(prev)
                        elseif seq[n][32] then -- somewhat special, as zapfino can have many preceding spaces
                            n = n - 1
                        else
                            match = false
                            break
                        end
                    end
                else
                    match = false
                end
            end
            -- after
            if match and s > l then
                local current = last and getnext(last)
                if current then
                    -- removed optimization for s-l == 1, we have to deal with marks anyway
                    local n = l + 1
                    while n <= s do
                        if current then
                            local id = getid(current)
                            if id == glyph_code then
                                if getfont(current) == currentfont and getsubtype(current)<256 then -- normal char
                                    local char = getchar(current)
                                    local ccd = descriptions[char] -- TODO: we have a marks array !
                                    if ccd then
                                        local class = ccd.class or "base"
                                        if class == skipmark or class == skipligature or class == skipbase or (markclass and class == "mark" and not markclass[char]) then
                                            skipped = true
                                            if trace_skips then
                                                show_skip(dataset,sequence,char,ck,class)
                                            end
                                        elseif seq[n][char] then
                                            n = n + 1
                                        else
                                            match = false
                                            break
                                        end
                                    else
                                        match = false
                                        break
                                    end
                                else
                                    match = false
                                    break
                                end
                            elseif id == disc_code then
                                if check_discretionaries then
                                    local replace = getfield(current,"replace")
                                    if replace then
                                        -- so far we never entered this branch
                                        while replace do
                                            if seq[n][getchar(replace)] then
                                                n = n + 1
                                                replace = getnext(replace)
                                                if not replace then
                                                    break
                                                elseif n > s then
                                                    break
                                                end
                                            else
                                                match = false
                                                break
                                            end
                                        end
                                        if not match then
                                            break
                                        elseif check_discretionaries == "trace" then
                                            report_chain("check disc action in after")
                                        end
                                    else
                                        -- skip 'm
                                    end
                                else
                                    -- skip 'm
                                end
                            elseif seq[n][32] then -- brrr
                                n = n + 1
                            else
                                match = false
                                break
                            end
                            current = getnext(current)
                        elseif seq[n][32] then
                            n = n + 1
                        else
                            match = false
                            break
                        end
                    end
                else
                    match = false
                end
            end
        end
        if match then
            -- can lookups be of a different type ?
            if trace_contexts then
                local rule       = ck[1]
                local lookuptype = ck[8]
                local first      = ck[4]
                local last       = ck[5]
                local char       = getchar(start)
                logwarning("%s: rule %s matches at char %s for (%s,%s,%s) chars, lookuptype %a",
                    cref(dataset,sequence),rule,gref(char),first-1,last-first+1,s-last,lookuptype)
            end
            local chainlookups = ck[6]
            if chainlookups then
                local nofchainlookups = #chainlookups
                -- we can speed this up if needed
                if nofchainlookups == 1 then
                    local chainlookup = chainlookups[1]
                    local chainkind   = chainlookup.type
                    local chainproc   = chainprocs[chainkind]
                    if chainproc then
                        local ok
                        head, start, ok = chainproc(head,start,last,dataset,sequence,chainlookup,rlmode,1)
                        if ok then
                            done = true
                        end
                    else
                        logprocess("%s: %s is not yet supported",cref(dataset,sequence),chainkind)
                    end
                 else
                    local i = 1
                    while start and true do
                        if skipped then
                            while true do -- todo: use properties
                                local char = getchar(start)
                                local ccd = descriptions[char]
                                if ccd then
                                    local class = ccd.class or "base"
                                    if class == skipmark or class == skipligature or class == skipbase or (markclass and class == "mark" and not markclass[char]) then
                                        start = getnext(start)
                                    else
                                        break
                                    end
                                else
                                    break
                                end
                            end
                        end
                        -- see remark in ms standard under : LookupType 5: Contextual Substitution Subtable
                        local chainlookup = chainlookups[1] -- should be i when they can be different
                        if not chainlookup then
                            -- we just advance
                            i = i + 1
                        else
                            local chainkind = chainlookup.type
                            local chainproc = chainprocs[chainkind]
                            if chainproc then
                                local ok, n
                                head, start, ok, n = chainproc(head,start,last,dataset,sequence,chainlookup,rlmode,i)
                                -- messy since last can be changed !
                                if ok then
                                    done = true
                                    if n and n > 1 then
                                        -- we have a ligature (cf the spec we advance one but we really need to test it
                                        -- as there are fonts out there that are fuzzy and have too many lookups:
                                        --
                                        -- U+1105 U+119E U+1105 U+119E : sourcehansansklight: script=hang ccmp=yes
                                        --
                                        if i + n > nofchainlookups then
                                         -- if trace_contexts then
                                         --     logprocess("%s: quitting lookups",cref(dataset,sequence))
                                         -- end
                                            break
                                        else
                                            -- we need to carry one
                                        end
                                    end
                                end
                            else
                                -- actually an error
                                logprocess("%s: %s is not yet supported",cref(dataset,sequence),chainkind)
                            end
                            i = i + 1
                        end
                        if i > nofchainlookups or not start then
                            break
                        elseif start then
                            start = getnext(start)
                        end
                    end
                end
            else
                local replacements = ck[7]
                if replacements then
                    head, start, done = chainprocs.reversesub(head,start,last,dataset,sequence,replacements,rlmode)
                else
                    done = quit_on_no_replacement -- can be meant to be skipped / quite inconsistent in fonts
                    if trace_contexts then
                        logprocess("%s: skipping match",cref(dataset,sequence))
                    end
                end
            end
        end
    end
    return head, start, done
end

handlers.gsub_context             = handle_contextchain
handlers.gsub_contextchain        = handle_contextchain
handlers.gsub_reversecontextchain = handle_contextchain
handlers.gpos_contextchain        = handle_contextchain
handlers.gpos_context             = handle_contextchain

local missing = setmetatableindex("table")

local function logprocess(...)
    if trace_steps then
        registermessage(...)
    end
    report_process(...)
end

local logwarning = report_process

local function report_missing_cache(dataset,sequence)
    local t = missing[currentfont]
    if not t[sequence] then
        t[sequence] = true
        logwarning("missing cache for feature %a, lookup %a, type %a, font %a, name %a",
            dataset[4],sequence.name,sequence.type,currentfont,tfmdata.properties.fullname)
    end
end

local resolved = { } -- we only resolve a font,script,language pair once

-- todo: pass all these 'locals' in a table

local sequencelists = setmetatableindex(function(t,font)
    local sequences = fontdata[font].resources.sequences
    if not sequences or not next(sequences) then
        sequences = false
    end
    t[font] = sequences
    return sequences
end)

-- fonts.hashes.sequences = sequencelists

local autofeatures = fonts.analyzers.features -- was: constants

local function initialize(sequence,script,language,enabled)
    local features = sequence.features
    if features then
        local order = sequence.order
        if order then
            for i=1,#order do --
                local kind  = order[i] --
                local valid = enabled[kind]
                if valid then
                    local scripts = features[kind] --
                    local languages = scripts[script] or scripts[wildcard]
                    if languages and (languages[language] or languages[wildcard]) then
                        return {
                            valid,
                            autofeatures[kind] or false,
                            sequence.chain or 0,
                            kind,
                            sequence,
                        }
                    end
                end
            end
        else
            -- can't happen
        end
    end
    return false
end

function otf.dataset(tfmdata,font) -- generic variant, overloaded in context
    local shared     = tfmdata.shared
    local properties = tfmdata.properties
    local language   = properties.language or "dflt"
    local script     = properties.script   or "dflt"
    local enabled    = shared.features
    local res = resolved[font]
    if not res then
        res = { }
        resolved[font] = res
    end
    local rs = res[script]
    if not rs then
        rs = { }
        res[script] = rs
    end
    local rl = rs[language]
    if not rl then
        rl = {
            -- indexed but we can also add specific data by key
        }
        rs[language] = rl
        local sequences = tfmdata.resources.sequences
        for s=1,#sequences do
            local v = enabled and initialize(sequences[s],script,language,enabled)
            if v then
                rl[#rl+1] = v
            end
        end
    end
    return rl
end

-- assumptions:
--
-- * languages that use complex disc nodes

-- optimization comes later ...

local function kernrun(disc,run) -- we can assume that prev and next are glyphs
    if trace_kernruns then
        report_run("kern") -- will be more detailed
    end
        --
    local prev = getprev(disc) -- todo, keep these in the main loop
    local next = getnext(disc) -- todo, keep these in the main loop
    --
    local pre = getfield(disc,"pre")
    if not pre then
        -- go on
    elseif prev then
        local nest = getprev(pre)
        setfield(pre,"prev",prev)
        setfield(prev,"next",pre)
        run(prev,"preinjections")
        setfield(pre,"prev",nest)
        setfield(prev,"next",disc)
    else
        run(pre,"preinjections")
    end
    --
    local post = getfield(disc,"post")
    if not post then
        -- go on
    elseif next then
        local tail = find_node_tail(post)
        setfield(tail,"next",next)
        setfield(next,"prev",tail)
        run(post,"postinjections",tail)
        setfield(tail,"next",nil)
        setfield(next,"prev",disc)
    else
        run(post,"postinjections")
    end
    --
    local replace = getfield(disc,"replace")
    if not replace then
        -- this should be already done by discfound
    elseif prev and next then
        local tail = find_node_tail(replace)
        local nest = getprev(replace)
        setfield(replace,"prev",prev)
        setfield(prev,"next",replace)
        setfield(tail,"next",next)
        setfield(next,"prev",tail)
        run(prev,"replaceinjections",tail)
        setfield(replace,"prev",nest)
        setfield(prev,"next",disc)
        setfield(tail,"next",nil)
        setfield(next,"prev",disc)
    elseif prev then
        local nest = getprev(replace)
        setfield(replace,"prev",prev)
        setfield(prev,"next",replace)
        run(prev,"replaceinjections")
        setfield(replace,"prev",nest)
        setfield(prev,"next",disc)
    elseif next then
        local tail = find_node_tail(replace)
        setfield(tail,"next",next)
        setfield(next,"prev",tail)
        run(replace,"replaceinjections",tail)
        setfield(tail,"next",nil)
        setfield(next,"prev",disc)
    else
        run(replace,"replaceinjections")
    end
end

-- the if new test might be dangerous as luatex will check / set some tail stuff
-- in a temp node

local function comprun(disc,run)
    if trace_compruns then
        report_run("comp: %s",languages.serializediscretionary(disc))
    end
    --
    local pre = getfield(disc,"pre")
    if pre then
        local new, done = run(pre)
        if done then
            setfield(disc,"pre",new)
        end
    end
    --
    local post = getfield(disc,"post")
    if post then
        local new, done = run(post)
        if done then
            setfield(disc,"post",new)
        end
    end
    --
    local replace = getfield(disc,"replace")
    if replace then
        local new, done = run(replace)
        if done then
            setfield(disc,"replace",new)
        end
    end
end

local function testrun(disc,trun,crun)
    local next = getnext(disc)
    if next then
        local replace = getfield(disc,"replace")
        if replace then
            local prev = getprev(disc)
            if prev then
                -- only look ahead
                local tail = find_node_tail(replace)
             -- local nest = getprev(replace)
                setfield(tail,"next",next)
                setfield(next,"prev",tail)
                if trun(replace,next) then
                    setfield(disc,"replace",nil) -- beware, side effects of nest so first
                    setfield(prev,"next",replace)
                    setfield(replace,"prev",prev)
                    setfield(next,"prev",tail)
                    setfield(tail,"next",next)
                    setfield(disc,"prev",nil)
                    setfield(disc,"next",nil)
                    flush_node_list(disc)
                    return replace -- restart
                else
                    setfield(tail,"next",nil)
                    setfield(next,"prev",disc)
                end
            else
                -- weird case
            end
        else
            -- no need
        end
    else
        -- weird case
    end
    comprun(disc,crun)
    return next
end

local function discrun(disc,drun,krun)
    local next = getnext(disc)
    local prev = getprev(disc)
    if trace_discruns then
        report_run("disc") -- will be more detailed
    end
    if next and prev then
        setfield(prev,"next",next)
     -- setfield(next,"prev",prev)
        drun(prev)
        setfield(prev,"next",disc)
     -- setfield(next,"prev",disc)
    end
    --
    local pre = getfield(disc,"pre")
    if not pre then
        -- go on
    elseif prev then
        local nest = getprev(pre)
        setfield(pre,"prev",prev)
        setfield(prev,"next",pre)
        krun(prev,"preinjections")
        setfield(pre,"prev",nest)
        setfield(prev,"next",disc)
    else
        krun(pre,"preinjections")
    end
    return next
end

-- todo: maybe run lr and rl stretches

local nesting = 0

local function featuresprocessor(head,font,attr)

    local sequences = sequencelists[font] -- temp hack

    if not sequencelists then
        return head, false
    end

    nesting = nesting + 1

    if nesting == 1 then

        currentfont     = font
        tfmdata         = fontdata[font]
        descriptions    = tfmdata.descriptions
        characters      = tfmdata.characters
        marks           = tfmdata.resources.marks
        factor          = tfmdata.parameters.factor

    elseif currentfont ~= font then

        report_warning("nested call with a different font, level %s, quitting",nesting)
        nesting = nesting - 1
        return head, false

    end

    head = tonut(head)

    if trace_steps then
        checkstep(head)
    end

    local rlmode    = 0
    local done      = false
    local datasets  = otf.dataset(tfmdata,font,attr)

    local dirstack  = { } -- could move outside function

    -- We could work on sub start-stop ranges instead but I wonder if there is that
    -- much speed gain (experiments showed that it made not much sense) and we need
    -- to keep track of directions anyway. Also at some point I want to play with
    -- font interactions and then we do need the full sweeps.

    -- Keeping track of the headnode is needed for devanagari (I generalized it a bit
    -- so that multiple cases are also covered.)

    -- We don't goto the next node of a disc node is created so that we can then treat
    -- the pre, post and replace. It's abit of a hack but works out ok for most cases.

    -- there can be less subtype and attr checking in the comprun etc helpers

    for s=1,#datasets do
        local dataset      = datasets[s]
        ----- featurevalue = dataset[1] -- todo: pass to function instead of using a global
        local attribute    = dataset[2]
        local chain        = dataset[3] -- sequence.chain or 0
        ----- kind         = dataset[4]
        local sequence     = dataset[5] -- sequences[s] -- also dataset[5]
        local rlparmode    = 0
        local topstack     = 0
        local success      = false
        local typ          = sequence.type
        local gpossing     = typ == "gpos_single" or typ == "gpos_pair"
        local handler      = handlers[typ]
        local steps        = sequence.steps
        local nofsteps     = sequence.nofsteps
        if chain < 0 then
            -- this is a limited case, no special treatments like 'init' etc
            -- we need to get rid of this slide! probably no longer needed in latest luatex
            local start = find_node_tail(head) -- slow (we can store tail because there's always a skip at the end): todo
            while start do
                local id = getid(start)
                if id == glyph_code then
                    if getfont(start) == font and getsubtype(start) < 256 then
                        local a = getattr(start,0)
                        if a then
                            a = a == attr
                        else
                            a = true
                        end
                        if a then
                            local char = getchar(start)
                            for i=1,nofsteps do
                                local step = steps[i]
                                local lookupcache = step.coverage
                                if lookupcache then
                                    local lookupmatch = lookupcache[char]
                                    if lookupmatch then
                                        -- todo: disc?
                                        head, start, success = handler(head,start,dataset,sequence,lookupmatch,rlmode,step,i)
                                        if success then
                                            break
                                        end
                                    end
                                else
                                    report_missing_cache(dataset,sequence)
                                end
                            end
                            if start then start = getprev(start) end
                        else
                            start = getprev(start)
                        end
                    else
                        start = getprev(start)
                    end
                else
                    start = getprev(start)
                end
            end
        else
            local start = head -- local ?
            rlmode = 0 -- to be checked ?
            if nofsteps == 1 then -- happens often
                local step = steps[1]
                local lookupcache = step.coverage
                if not lookupcache then -- also check for empty cache
                    report_missing_cache(dataset,sequence)
                else

                    local function c_run(start) -- no need to check for 256 and attr probably also the same
                        local head = start
                        local done = false
                        while start do
                            local id = getid(start)
                            if id ~= glyph_code then
                                -- very unlikely
                                start = getnext(start)
                            elseif getfont(start) == font and getsubtype(start) < 256 then
                                local a = getattr(start,0)
                                if a then
                                    a = (a == attr) and (not attribute or getprop(start,a_state) == attribute)
                                else
                                    a = not attribute or getprop(start,a_state) == attribute
                                end
                                if a then
                                    local lookupmatch = lookupcache[getchar(start)]
                                    if lookupmatch then
                                        -- sequence kan weg
                                        local ok
                                        head, start, ok = handler(head,start,dataset,sequence,lookupmatch,rlmode,step,1)
                                        if ok then
                                            done = true
                                        end
                                    end
                                    if start then start = getnext(start) end
                                else
                                    start = getnext(start)
                                end
                            else
                                return head, false
                            end
                        end
                        if done then
                            success = true -- needed in this subrun?
                        end
                        return head, done
                    end

                    local function t_run(start,stop)
                        while start ~= stop do
                            local id = getid(start)
                            if id == glyph_code and getfont(start) == font and getsubtype(start) < 256 then
                                local a = getattr(start,0)
                                if a then
                                    a = (a == attr) and (not attribute or getprop(start,a_state) == attribute)
                                else
                                    a = not attribute or getprop(start,a_state) == attribute
                                end
                                if a then
                                    local lookupmatch = lookupcache[getchar(start)]
                                    if lookupmatch then -- hm, hyphens can match (tlig) so we need to really check
                                        -- if we need more than ligatures we can outline the code and use functions
                                        local s = getnext(start)
                                        local l = nil
                                        while s do
                                            local lg = lookupmatch[getchar(s)]
                                            if lg then
                                                l = lg
                                                s = getnext(s)
                                            else
                                                break
                                            end
                                        end
                                        if l and l.ligature then
                                            return true
                                        end
                                    end
                                end
                                start = getnext(start)
                            else
                                break
                            end
                        end
                    end

                    local function d_run(prev) -- we can assume that prev and next are glyphs
                        local a = getattr(prev,0)
                        if a then
                            a = (a == attr) and (not attribute or getprop(prev,a_state) == attribute)
                        else
                            a = not attribute or getprop(prev,a_state) == attribute
                        end
                        if a then
                            local lookupmatch = lookupcache[getchar(prev)]
                            if lookupmatch then
                                -- sequence kan weg
                                local h, d, ok = handler(head,start,dataset,sequence,lookupmatch,rlmode,step,1)
                                if ok then
                                    done = true
                                    success = true
                                end
                            end
                        end
                    end

                    local function k_run(sub,injection,last)
                        local a = getattr(sub,0)
                        if a then
                            a = (a == attr) and (not attribute or getprop(sub,a_state) == attribute)
                        else
                            a = not attribute or getprop(sub,a_state) == attribute
                        end
                        if a then
                            -- sequence kan weg
                            for n in traverse_nodes(sub) do -- only gpos
                                if n == last then
                                    break
                                end
                                local id = getid(n)
                                if id == glyph_code then
                                    local lookupmatch = lookupcache[getchar(n)]
                                    if lookupmatch then
                                        local h, d, ok = handler(sub,n,dataset,sequence,lookupmatch,rlmode,step,1,injection)
                                        if ok then
                                            done = true
                                            success = true
                                        end
                                    end
                                else
                                    -- message
                                end
                            end
                        end
                    end

                    while start do
                        local id = getid(start)
                        if id == glyph_code then
                            if getfont(start) == font and getsubtype(start) < 256 then -- why a 256 test ...
                                local a = getattr(start,0)
                                if a then
                                    a = (a == attr) and (not attribute or getprop(start,a_state) == attribute)
                                else
                                    a = not attribute or getprop(start,a_state) == attribute
                                end
                                if a then
                                    local char        = getchar(start)
                                    local lookupmatch = lookupcache[char]
                                    if lookupmatch then
                                        -- sequence kan weg
                                        local ok
                                        head, start, ok = handler(head,start,dataset,sequence,lookupmatch,rlmode,step,1)
                                        if ok then
                                            success = true
                                        elseif gpossing and zwnjruns and char == zwnj then
                                            discrun(start,d_run)
                                        end
                                    elseif gpossing and zwnjruns and char == zwnj then
                                        discrun(start,d_run)
                                    end
                                    if start then start = getnext(start) end
                                else
                                   start = getnext(start)
                                end
                            else
                                start = getnext(start)
                            end
                        elseif id == disc_code then
                           local discretionary = getsubtype(start) == discretionary_code
                           if gpossing then
                               if discretionary then
                                   kernrun(start,k_run)
                               else
                                   discrun(start,d_run,k_run)
                               end
                               start = getnext(start)
                           elseif discretionary then
                               if typ == "gsub_ligature" then
                                   start = testrun(start,t_run,c_run)
                               else
                                   comprun(start,c_run)
                                   start = getnext(start)
                               end
                           else
                                start = getnext(start)
                           end
                        elseif id == whatsit_code then -- will be function
                            local subtype = getsubtype(start)
                            if subtype == dir_code then
                                local dir = getfield(start,"dir")
                                if     dir == "+TRT" or dir == "+TLT" then
                                    topstack = topstack + 1
                                    dirstack[topstack] = dir
                                elseif dir == "-TRT" or dir == "-TLT" then
                                    topstack = topstack - 1
                                end
                                local newdir = dirstack[topstack]
                                if newdir == "+TRT" then
                                    rlmode = -1
                                elseif newdir == "+TLT" then
                                    rlmode = 1
                                else
                                    rlmode = rlparmode
                                end
                                if trace_directions then
                                    report_process("directions after txtdir %a: parmode %a, txtmode %a, # stack %a, new dir %a",dir,mref(rlparmode),mref(rlmode),topstack,mref(newdir))
                                end
                            elseif subtype == localpar_code then
                                local dir = getfield(start,"dir")
                                if dir == "TRT" then
                                    rlparmode = -1
                                elseif dir == "TLT" then
                                    rlparmode = 1
                                else
                                    rlparmode = 0
                                end
                                -- one might wonder if the par dir should be looked at, so we might as well drop the next line
                                rlmode = rlparmode
                                if trace_directions then
                                    report_process("directions after pardir %a: parmode %a, txtmode %a",dir,mref(rlparmode),mref(rlmode))
                                end
                            end
                            start = getnext(start)
                        elseif id == math_code then
                            start = getnext(end_of_math(start))
                        else
                            start = getnext(start)
                        end
                    end
                end

            else

                local function c_run(start)
                    local head = start
                    local done = false
                    while start do
                        local id = getid(start)
                        if id ~= glyph_code then
                            -- very unlikely
                            start = getnext(start)
                        elseif getfont(start) == font and getsubtype(start) < 256 then
                            local a = getattr(start,0)
                            if a then
                                a = (a == attr) and (not attribute or getprop(start,a_state) == attribute)
                            else
                                a = not attribute or getprop(start,a_state) == attribute
                            end
                            if a then
                                local char = getchar(start)
                                local lookupcache = step.coverage
                                for i=1,nofsteps do
                                    local step = steps[i]
                                    local lookupcache = step.coverage
                                    if lookupcache then
                                        local lookupmatch = lookupcache[char]
                                        if lookupmatch then
                                            -- we could move all code inline but that makes things even more unreadable
                                            local ok
                                            head, start, ok = handler(head,start,dataset,sequence,lookupmatch,rlmode,step,i)
                                            if ok then
                                                done = true
                                                break
                                            elseif not start then
                                                -- don't ask why ... shouldn't happen
                                                break
                                            end
                                        end
                                    else
                                        report_missing_cache(dataset,sequence)
                                    end
                                end
                                if start then start = getnext(start) end
                            else
                                start = getnext(start)
                            end
                        else
                            return head, false
                        end
                    end
                    if done then
                        success = true
                    end
                    return head, done
                end

                local function d_run(prev)
                    local a = getattr(prev,0)
                    if a then
                        a = (a == attr) and (not attribute or getprop(prev,a_state) == attribute)
                    else
                        a = not attribute or getprop(prev,a_state) == attribute
                    end
                    if a then
                        -- brr prev can be disc
                        local char = getchar(prev)
                        for i=1,nofsteps do
                            local step        = steps[i]
                            local lookupcache = step.coverage
                            if lookupcache then
                                local lookupmatch = lookupcache[char]
                                if lookupmatch then
                                    -- we could move all code inline but that makes things even more unreadable
                                    local h, d, ok = handler(head,prev,dataset,sequence,lookupmatch,rlmode,step,i)
                                    if ok then
                                        done = true
                                        break
                                    end
                                end
                            else
                                report_missing_cache(dataset,sequence)
                            end
                        end
                    end
                end

               local function k_run(sub,injection,last)
                    local a = getattr(sub,0)
                    if a then
                        a = (a == attr) and (not attribute or getprop(sub,a_state) == attribute)
                    else
                        a = not attribute or getprop(sub,a_state) == attribute
                    end
                    if a then
                        for n in traverse_nodes(sub) do -- only gpos
                            if n == last then
                                break
                            end
                            local id = getid(n)
                            if id == glyph_code then
                                local char = getchar(n)
                                for i=1,nofsteps do
                                    local step = steps[i]
                                    local lookupcache = step.coverage
                                    if lookupcache then
                                        local lookupmatch = lookupcache[char]
                                        if lookupmatch then
                                            local h, d, ok = handler(head,n,dataset,sequence,lookupmatch,step,rlmode,i,injection)
                                            if ok then
                                                done = true
                                                break
                                            end
                                        end
                                    else
                                        report_missing_cache(dataset,sequence)
                                    end
                                end
                            else
                                -- message
                            end
                        end
                    end
                end

                local function t_run(start,stop)
                    while start ~= stop do
                        local id = getid(start)
                        if id == glyph_code and getfont(start) == font and getsubtype(start) < 256 then
                            local a = getattr(start,0)
                            if a then
                                a = (a == attr) and (not attribute or getprop(start,a_state) == attribute)
                            else
                                a = not attribute or getprop(start,a_state) == attribute
                            end
                            if a then
                                local char = getchar(start)
                                for i=1,nofsteps do
                                    local step = steps[i]
                                    local lookupcache = step.coverage
                                    if lookupcache then
                                        local lookupmatch = lookupcache[char]
                                        if lookupmatch then
                                            -- if we need more than ligatures we can outline the code and use functions
                                            local s = getnext(start)
                                            local l = nil
                                            while s do
                                                local lg = lookupmatch[getchar(s)]
                                                if lg then
                                                    l = lg
                                                    s = getnext(s)
                                                else
                                                    break
                                                end
                                            end
                                            if l and l.ligature then
                                                return true
                                            end
                                        end
                                    else
                                        report_missing_cache(dataset,sequence)
                                    end
                                end
                            end
                            start = getnext(start)
                        else
                            break
                        end
                    end
                end

                while start do
                    local id = getid(start)
                    if id == glyph_code then
                        if getfont(start) == font and getsubtype(start) < 256 then
                            local a = getattr(start,0)
                            if a then
                                a = (a == attr) and (not attribute or getprop(start,a_state) == attribute)
                            else
                                a = not attribute or getprop(start,a_state) == attribute
                            end
                            if a then
                                for i=1,nofsteps do
                                    local step = steps[i]
                                    local lookupcache = step.coverage
                                    if lookupcache then
                                        local char = getchar(start)
                                        local lookupmatch = lookupcache[char]
                                        if lookupmatch then
                                            -- we could move all code inline but that makes things even more unreadable
                                            local ok
                                            head, start, ok = handler(head,start,dataset,sequence,lookupmatch,rlmode,step,i)
                                            if ok then
                                                success = true
                                                break
                                            elseif not start then
                                                -- don't ask why ... shouldn't happen
                                                break
                                            elseif gpossing and zwnjruns and char == zwnj then
                                                discrun(start,d_run)
                                            end
                                        elseif gpossing and zwnjruns and char == zwnj then
                                            discrun(start,d_run)
                                        end
                                    else
                                        report_missing_cache(dataset,sequence)
                                    end
                                end
                                if start then start = getnext(start) end
                            else
                                start = getnext(start)
                            end
                        else
                            start = getnext(start)
                        end
                    elseif id == disc_code then
                        local discretionary = getsubtype(start) == discretionary_code
                        if gpossing then
                            if discretionary then
                                kernrun(start,k_run)
                            else
                                discrun(start,d_run,k_run)
                            end
                            start = getnext(start)
                        elseif discretionary then
                            if typ == "gsub_ligature" then
                                start = testrun(start,t_run,c_run)
                            else
                                comprun(start,c_run)
                                start = getnext(start)
                            end
                        else
                            start = getnext(start)
                        end
                    elseif id == whatsit_code then
                        local subtype = getsubtype(start)
                        if subtype == dir_code then
                            local dir = getfield(start,"dir")
                            if     dir == "+TRT" or dir == "+TLT" then
                                topstack = topstack + 1
                                dirstack[topstack] = dir
                            elseif dir == "-TRT" or dir == "-TLT" then
                                topstack = topstack - 1
                            end
                            local newdir = dirstack[topstack]
                            if newdir == "+TRT" then
                                rlmode = -1
                            elseif newdir == "+TLT" then
                                rlmode = 1
                            else
                                rlmode = rlparmode
                            end
                            if trace_directions then
                                report_process("directions after txtdir %a: parmode %a, txtmode %a, # stack %a, new dir %a",dir,mref(rlparmode),mref(rlmode),topstack,mref(newdir))
                            end
                        elseif subtype == localpar_code then
                            local dir = getfield(start,"dir")
                            if dir == "TRT" then
                                rlparmode = -1
                            elseif dir == "TLT" then
                                rlparmode = 1
                            else
                                rlparmode = 0
                            end
                            rlmode = rlparmode
                            if trace_directions then
                                report_process("directions after pardir %a: parmode %a, txtmode %a",dir,mref(rlparmode),mref(rlmode))
                            end
                        end
                        start = getnext(start)
                    elseif id == math_code then
                        start = getnext(end_of_math(start))
                    else
                        start = getnext(start)
                    end
                end
            end
        end
        if success then
            done = true
        end
        if trace_steps then -- ?
            registerstep(head)
        end

    end

    nesting = nesting - 1
    head    = tonode(head)

    return head, done
end

-- so far

local function featuresinitializer(tfmdata,value)
    -- nothing done here any more
end

registerotffeature {
    name         = "features",
    description  = "features",
    default      = true,
    initializers = {
        position = 1,
        node     = featuresinitializer,
    },
    processors   = {
        node     = featuresprocessor,
    }
}

-- This can be used for extra handlers, but should be used with care!

otf.handlers = handlers -- used in devanagari