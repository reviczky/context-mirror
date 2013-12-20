if not modules then modules = { } end modules ['node-par'] = {
    version   = 1.001,
    comment   = "companion to node-par.mkiv",
    author    = "Hans Hagen",
    copyright = "ConTeXt Development Team",
    license   = "see context related readme files",
    comment   = "a translation of the built in parbuilder, initial convertsin by Taco Hoekwater",
}

-- todo: remove nest_stack from linebreak.w
-- todo: use ex field as signal (index in ?)
-- todo: attr driven unknown/on/off
-- todo: permit global steps i.e. using an attribute that sets min/max/step and overloads the font parameters
-- todo: split the three passes into three functions
-- todo: simplify the direction stack, no copy needed
-- todo: see if we can do without delta nodes (needs thinking)
-- todo: add more mkiv like tracing
-- todo: add a couple of plugin hooks
-- todo: maybe split expansion code paths
-- todo: fix line numbers (cur_list.pg_field needed)
-- todo: make kerns stretch an option and disable it by default (definitely not shrink)
-- todo: check and improve protrusion
-- todo: arabic etc (we could use pretty large scales there) .. marks and cursive

--[[

    This code is derived from traditional TeX and has bits of pdfTeX, Aleph (Omega), and of course LuaTeX. So,
    the basic algorithm for sure is not our work. On the other hand, the directional model in LuaTeX is cleaned
    up as is other code. And of course there are hooks for callbacks.

    The first version of the code below was a conversion of the C code that in turn was a conversion from the
    original Pascal code. Around September 2008 we experimented with cq. discussed possible approaches to improved
    typesetting of Arabic and as our policy is that extensions happen in Lua this means that we need a parbuilder
    in Lua. Taco's first conversion still looked quite C-ish and in the process of cleaning up we uncovered some odd
    bits and pieces in the original code as well. I did some first cleanup to get rid of C-artefacts, and Taco and I
    spent the usual amount of Skyping to sort out problems. At that point we diverted to other LuaTeX issues.

    A while later I decided to pick up this thread and decided to look into better ways to deal with font expansion
    (aka hz). I got it running using a simpler method. One reason why the built-in mechanims is slow is that there is
    lots of redudancy in calculations. Expanded widths are recalculated each time and because the hpakc routine does
    it again that gives some overhead. In the process extra fonts are created with different dimensions so that the
    backend can deal with it. The alternative method doesn't create fonts but passes an expansion factor to the
    pdf generator. The small patch needed for the backend code worked more or less okay but was never intergated into
    LuaTeX due to lack of time.

    This all happened in 2010 while listening to Peter Gabriels "Scratch My Back" and Camels "Rayaz" so it was a
    rather relaxed job.

    In 2012 I picked up this thread. Because both languages are similar but also quite different it took some time
    to get compatible output. Because the C code uses macros, careful checking was needed. Of course Lua's table model
    and local variables brought some work as well. And still the code looks a bit C-ish. We could not divert too much
    from the original model simply because it's well documented but future versions (or variants) might as well look
    different.

    Eventually I'll split this code into passes so that we can better see what happens, but first we need to reach
    a decent level of stability. The current expansion results are not the same as the built-in but that was never
    the objective. It all has to do with slightly different calculations.

    The original C-code related to protrusion and expansion is not that efficient as many (redundant) function
    calls take place in the linebreaker and packer. As most work related to fonts is done in the backend, we
    can simply stick to width calculations here. Also, it is no problem at all that we use floating point
    calculations (as Lua has only floats). The final result will look ok as the hpack will nicely compensate
    for rounding errors as it will normally distribute the content well enough. And let's admit: most texies
    won't see it anyway. As long as we're cross platform compatible it's fine.

    We use the table checked_expansion to keep track of font related parameters (per paragraph). The table is
    also the signal that we have adjustments > 1. In retrospect one might wonder if adjusting kerns is such a
    good idea because other spacing is also not treated. If we would stick to the regular hpack routine
    we do have to follow the same logic, but I decided to use a Lua hpacker so that constraint went away. And
    anyway, instead of doing a lookup in the kern table (that we don't have in node mode) the set kern value
    is used. Disabling kern scaling will become an option in Luatex some day. You can blame me for all errors
    that crept in and I know that there are some.

    To be honest, I slowly start to grasp the magic here as normally I start from scratch when implementing
    something (as it's the only way I can understand things). This time I had a recently acquired stack of
    Porcupine Tree disks to get me through.

    Picking up this effort was inspired by discussions between Luigi Scarso and me about efficiency of Lua
    code and we needed some stress tests to compare regular LuaTeX and LuajitTeX. One of the tests was
    processing tufte.tex as that one has lots of hyphenations and is a tough one to get right.

    tufte: boxed 1000 times, no flushing in backend:

                           \testfeatureonce{1000}{\setbox0\hbox{\tufte}}
                           \testfeatureonce{1000}{\setbox0\vbox{\tufte}}
    \startparbuilder[basic]\testfeatureonce{1000}{\setbox0\vbox{\tufte}}\stopparbuilder

                method     normal   hz      comment

    luatex      tex hbox    9.64     9.64   baseline font feature processing, hyphenation etc: 9.74
                tex vbox    9.84    10.16   0.20 linebreak / 0.52 with hz -> 0.32 hz overhead (150pct more)
                lua vbox   17.28    18.43   7.64 linebreak / 8.79 with hz -> 1.33 hz overhead ( 20pct more)

    new laptop | no nuts
                            3.42            baseline
                            3.63            0.21 linebreak
                            7.38            3.96 linebreak

    new laptop | most nuts
                            2.45            baseline
                            2.53            0.08 linebreak
                            6.16            3.71 linebreak
                 ltp nuts   5.45            3.00 linebreak

    luajittex   tex hbox    6.33     6.33   baseline font feature processing, hyphenation etc: 6.33
                tex vbox    6.53     6.81   0.20 linebreak / 0.48 with hz -> 0.28 hz overhead (expected 0.32)
                lua vbox   11.06    11.81   4.53 linebreak / 5.28 with hz -> 0.75 hz overhead

    new laptop | no nuts
                            2.06            baseline
                            2.27            0.21 linebreak
                            3.95            1.89 linebreak

    new laptop | most nuts
                            1.25            baseline
                            1.30            0.05 linebreak
                            3.03            1.78 linebreak
                 ltp nuts   2.47            1.22 linebreak

    Interesting is that the runtime for the built-in parbuilder indeed increases much when expansion
    is enabled, but in the Lua variant the extra overhead is way less significant. This means that when we
    retrofit the same approach into the core, the overhead of expansion can be sort of nilled.

]]--

local utfchar = utf.char
local write, write_nl = texio.write, texio.write_nl
local sub, format = string.sub, string.format
local round, floor = math.round, math.floor
local insert, remove = table.insert, table.remove

local fonts, nodes, node = fonts, nodes, node

local trace_basic         = false  trackers.register("builders.paragraphs.basic",       function(v) trace_basic       = v end)
local trace_lastlinefit   = false  trackers.register("builders.paragraphs.lastlinefit", function(v) trace_lastlinefit = v end)
local trace_adjusting     = false  trackers.register("builders.paragraphs.adjusting",   function(v) trace_adjusting   = v end)
local trace_protruding    = false  trackers.register("builders.paragraphs.protruding",  function(v) trace_protruding  = v end)
local trace_expansion     = false  trackers.register("builders.paragraphs.expansion",   function(v) trace_expansion   = v end)
local trace_quality       = false  trackers.register("builders.paragraphs.quality",     function(v) trace_quality     = v end)

local report_parbuilders  = logs.reporter("nodes","parbuilders")
local report_hpackers     = logs.reporter("nodes","hpackers")

local calculate_badness   = tex.badness
local texnest             = tex.nest
local texlists            = tex.lists

-- (t == 0 and 0) or (s <= 0 and 10000) or calculate_badness(t,s)

-- local function calculate_badness(t,s)
--     if t == 0 then
--         return 0
--     elseif s <= 0 then
--         return 10000 -- infinite_badness
--     else
--         local r
--         if t <= 7230584 then
--             r = (t * 297) / s
--         elseif s >= 1663497 then
--             r = t / (s / 297)
--         else
--             r = t
--         end
--         if r > 1290 then
--             return 10000 -- infinite_badness
--         else
--             return (r * r * r + 0x20000) / 0x40000
--         end
--     end
-- end

local parbuilders          = builders.paragraphs
local constructors         = parbuilders.constructors

local setmetatableindex    = table.setmetatableindex

local fonthashes           = fonts.hashes
local fontdata             = fonthashes.identifiers
local chardata             = fonthashes.characters
local quaddata             = fonthashes.quads
local parameters           = fonthashes.parameters

local slide_nodes          = node.slide
local new_node             = node.new
local copy_node            = node.copy
local copy_node_list       = node.copy_list
local flush_node           = node.free
local flush_node_list      = node.flush_list
local hpack_nodes          = node.hpack
local xpack_nodes          = node.hpack
local replace_node         = nodes.replace
local insert_node_after    = node.insert_after
local insert_node_before   = node.insert_before
local traverse_by_id       = node.traverse_id

local setnodecolor         = nodes.tracers.colors.set

local nodepool             = nodes.pool

local nodecodes            = nodes.nodecodes
local whatcodes            = nodes.whatcodes
local kerncodes            = nodes.kerncodes
local glyphcodes           = nodes.glyphcodes
local gluecodes            = nodes.gluecodes
local margincodes          = nodes.margincodes
local disccodes            = nodes.disccodes
local mathcodes            = nodes.mathcodes
local fillcodes            = nodes.fillcodes

local temp_code            = nodecodes.temp
local glyph_code           = nodecodes.glyph
local ins_code             = nodecodes.ins
local mark_code            = nodecodes.mark
local adjust_code          = nodecodes.adjust
local penalty_code         = nodecodes.penalty
local whatsit_code         = nodecodes.whatsit
local disc_code            = nodecodes.disc
local math_code            = nodecodes.math
local kern_code            = nodecodes.kern
local glue_code            = nodecodes.glue
local hlist_code           = nodecodes.hlist
local vlist_code           = nodecodes.vlist
local unset_code           = nodecodes.unset
local marginkern_code      = nodecodes.marginkern

local leaders_code         = gluecodes.leaders

local localpar_code        = whatcodes.localpar
local dir_code             = whatcodes.dir
local pdfrefximage_code    = whatcodes.pdfrefximage
local pdfrefxform_code     = whatcodes.pdfrefxform

local kerning_code         = kerncodes.kerning -- font kern
local userkern_code        = kerncodes.userkern

local ligature_code        = glyphcodes.ligature

local stretch_orders       = nodes.fillcodes

local leftmargin_code      = margincodes.left
local rightmargin_code     = margincodes.right

local automatic_disc_code  = disccodes.automatic
local regular_disc_code    = disccodes.regular
local first_disc_code      = disccodes.first
local second_disc_code     = disccodes.second

local endmath_code         = mathcodes.endmath

local nosubtype_code       = 0

local unhyphenated_code    = nodecodes.unhyphenated or 1
local hyphenated_code      = nodecodes.hyphenated   or 2
local delta_code           = nodecodes.delta        or 3
local passive_code         = nodecodes.passive      or 4

local maxdimen             = number.maxdimen

local max_halfword         = 0x7FFFFFFF
local infinite_penalty     =  10000
local eject_penalty        = -10000
local infinite_badness     =  10000
local awful_badness        = 0x3FFFFFFF

local fit_very_loose_class = 0  -- fitness for lines stretching more than their stretchability
local fit_loose_class      = 1  -- fitness for lines stretching 0.5 to 1.0 of their stretchability
local fit_decent_class     = 2  -- fitness for all other lines
local fit_tight_class      = 3  -- fitness for lines shrinking 0.5 to 1.0 of their shrinkability

local new_penalty          = nodepool.penalty
local new_dir              = nodepool.textdir
local new_leftmarginkern   = nodepool.leftmarginkern
local new_rightmarginkern  = nodepool.rightmarginkern
local new_leftskip         = nodepool.leftskip
local new_rightskip        = nodepool.rightskip
local new_lineskip         = nodepool.lineskip
local new_baselineskip     = nodepool.baselineskip
local new_temp             = nodepool.temp
local new_rule             = nodepool.rule

local is_rotated           = nodes.is_rotated
local is_parallel          = nodes.textdir_is_parallel
local is_opposite          = nodes.textdir_is_opposite
local textdir_is_equal     = nodes.textdir_is_equal
local pardir_is_equal      = nodes.pardir_is_equal
local glyphdir_is_equal    = nodes.glyphdir_is_equal

local dir_pops             = nodes.dir_is_pop
local dir_negations        = nodes.dir_negation
local is_skipable          = node.protrusion_skippable
local a_fontkern           = attributes.private('fontkern')

-- helpers --

-- It makes more sense to move the somewhat messy dir state tracking
-- out of the main functions. First we create a stack allocator.

local function new_dir_stack(dir) -- also use elsewhere
    return { n = 0, dir }
end

-- The next function checks a dir node and returns the new dir state. By
-- using s static table we are quite efficient. This function is used
-- in the parbuilder.

local function checked_line_dir(stack,current)
    if not dir_pops[current] then
        local n = stack.n + 1
        stack.n = n
        stack[n] = current
        return current.dir
    elseif n > 0 then
        local n = stack.n
        local dirnode = stack[n]
        dirstack.n = n - 1
        return dirnode.dir
    else
        report_parbuilders("warning: missing pop node (%a)",1) -- in line ...
    end
end

-- The next function checks a dir nodes in a list and appends the negations
-- that are currently needed (some day LuaTeX will be more tolerant). We use
-- the negations for the next line.

local function inject_dirs_at_end_of_line(stack,current,start,stop)
    local e = start
    local n = stack.n
    local h = nil
    while start and start ~= stop do
        if start.id == whatsit_code and start.subtype == dir_code then
            if not dir_pops[start.dir] then
                n = n + 1
                stack[n] = start
            elseif n > 0 then
                n = n - 1
            else
                report_parbuilders("warning: missing pop node (%a)",2) -- in line ...
            end
        end
        start = start.next
    end
    for i=n,1,-1 do
        h, current = insert_node_after(current,current,new_dir(dir_negations[stack[i].dir]))
    end
    stack.n = n
    return current
end

local function inject_dirs_at_begin_of_line(stack,current)
    local h = nil
    for i=stack.n,1,-1 do
        h, current = insert_node_after(current,current,new_dir(stack[i]))
    end
    stack.n = 0
    return current
end

-- diagnostics --

local dummy = function() end

local diagnostics = {
    start          = dummy,
    stop           = dummy,
    current_pass   = dummy,
    break_node     = dummy,
    feasible_break = dummy,
}

-- statistics --

local nofpars, noflines, nofprotrudedlines, nofadjustedlines = 0, 0, 0, 0

local function register_statistics(par)
    local statistics  = par.statistics
    nofpars           = nofpars           + 1
    noflines          = noflines          + statistics.noflines
    nofprotrudedlines = nofprotrudedlines + statistics.nofprotrudedlines
    nofadjustedlines  = nofadjustedlines  + statistics.nofadjustedlines
end

-- resolvers --

local whatsiters = {
    get_width      = { },
    get_dimensions = { },
}

local get_whatsit_width      = whatsiters.get_width
local get_whatsit_dimensions = whatsiters.get_dimensions

local function get_width     (n) return n.width end
local function get_dimensions(n) return n.width, n.height, n.depth end

get_whatsit_width[pdfrefximage_code] = get_width
get_whatsit_width[pdfrefxform_code ] = get_width

get_whatsit_dimensions[pdfrefximage_code] = get_dimensions
get_whatsit_dimensions[pdfrefxform_code ] = get_dimensions

-- expansion etc --

local function calculate_fraction(x,n,d,max_answer)
    local the_answer = x * n/d + 1/2 -- round ?
    if the_answer > max_answer then
        return  max_answer
    elseif the_answer < -max_answer then
        return -max_answer
    else
        return  the_answer
    end
end

local function check_shrinkage(par,n)
    -- called often, so maybe move inline -- use NORMAL
    if n.shrink_order ~= 0 and n.shrink ~= 0 then
        if par.no_shrink_error_yet then
            par.no_shrink_error_yet = false
            report_parbuilders("infinite glue shrinkage found in a paragraph and removed")
        end
        n = copy_node(n)
        n.shrink_order = 0
    end
    return n
end

-- It doesn't really speed up much but the additional memory usage is
-- rather small so it doesn't hurt too much.

local expansions = { }
local nothing    = { stretch = 0, shrink = 0 }

setmetatableindex(expansions,function(t,font) -- we can store this in tfmdata if needed
    local expansion = parameters[font].expansion -- can be an extra hash
    if expansion and expansion.auto then
        local factors = { }
        local c = chardata[font]
        setmetatableindex(factors,function(t,char)
            local fc = c[char]
            local ef = fc.expansion_factor
            if ef and ef > 0 then
                local stretch = expansion.stretch
                local shrink  = expansion.shrink
                if stretch ~= 0 or shrink ~= 0 then
                    local factor  = ef / 1000
                    local ef_quad = factor * quaddata[font] / 1000
                    local v = {
                        glyphstretch = stretch * ef_quad,
                        glyphshrink  = shrink  * ef_quad,
                        factor       = factor,
                        stretch      = stretch,
                        shrink       = shrink,
                    }
                    t[char] = v
                    return v
                end
            end
            t[char] = nothing
            return nothing
        end)
        t[font] = factors
        return factors
    else
        t[font] = false
        return false
    end
end)

-- local function char_stretch_shrink(p)
--     local data = expansions[p.font][p.char]
--     if data then
--         return data.glyphstretch, data.glyphshrink
--     else
--         return 0, 0
--     end
-- end
--
-- local cal_margin_kern_var = char_stretch_shrink

-- local function kern_stretch_shrink(p,d)
--     local l = p.prev
--     if l and l.id == glyph_code then -- how about disc nodes?
--         local r = p.next
--         if r and r.id == glyph_code then
--             local lf, rf = l.font, r.font
--             if lf == rf then
--                 local data = expansions[lf][l.char]
--                 if data then
--                     local stretch = data.stretch
--                     local shrink  = data.shrink
--                     if stretch ~= 0 then
--                      -- stretch = data.factor * (d *  stretch - d)
--                         stretch = data.factor *  d * (stretch - 1)
--                     end
--                     if shrink ~= 0 then
--                      -- shrink = data.factor * (d *  shrink - d)
--                         shrink = data.factor *  d * (shrink - 1)
--                     end
--                     return stretch, shrink
--                 end
--             end
--         end
--     end
--     return 0, 0
-- end

local function kern_stretch_shrink(p,d)
    local left = p.prev
    if left and left.id == glyph_code then -- how about disc nodes?
        local data = expansions[left.font][left.char]
        if data then
            local stretch = data.stretch
            local shrink  = data.shrink
            if stretch ~= 0 then
             -- stretch = data.factor * (d *  stretch - d)
                stretch = data.factor *  d * (stretch - 1)
            end
            if shrink ~= 0 then
             -- shrink = data.factor * (d *  shrink - d)
                shrink = data.factor *  d * (shrink - 1)
            end
            return stretch, shrink
        end
    end
    return 0, 0
end

-- local function kern_stretch_shrink(p,d)
--     -- maybe make it an option in luatex where we also need to check for attribute fontkern but in general
--     -- it makes no sense to scale kerns
--     return 0, 0
-- end

local expand_kerns = false
-- local expand_kerns = "both"

directives.register("builders.paragraphs.adjusting.kerns",function(v)
    if not v then
        expand_kerns = false
    elseif v == "stretch" or v == "shrink" then
        expand_kerns = v
    elseif v == "both" then
        expand_kerns = true
    else
        expand_kerns = toboolean(v,true) or false
    end
end)

-- state:

local function check_expand_pars(checked_expansion,f)
    local expansion = parameters[f].expansion
    if not expansion then
        checked_expansion[f] = false
        return false
    end
-- expansion.step = 1
    local step    = expansion.step    or 0
    local stretch = expansion.stretch or 0
    local shrink  = expansion.shrink  or 0
    if step == 0 or (stretch == 0 and schrink == 0) then
        checked_expansion[f] = false
        return false
    end
    local par = checked_expansion.par
    if par.cur_font_step < 0 then
        par.cur_font_step = step
    elseif par.cur_font_step ~= step then
        report_parbuilders("using fonts with different step of expansion in one paragraph is not allowed")
        checked_expansion[f] = false
        return false
    end
    if stretch == 0 then
        -- okay
    elseif par.max_stretch_ratio < 0 then
        par.max_stretch_ratio = stretch -- expansion_factor
    elseif par.max_stretch_ratio ~= stretch then
        report_parbuilders("using fonts with different stretch limit of expansion in one paragraph is not allowed")
        checked_expansion[f] = false
        return false
    end
    if shrink == 0 then
        -- okay
    elseif par.max_shrink_ratio < 0 then
        par.max_shrink_ratio = shrink -- - expansion_factor
    elseif par.max_shrink_ratio ~= shrink then
        report_parbuilders("using fonts with different shrink limit of expansion in one paragraph is not allowed")
        checked_expansion[f] = false
        return false
    end
    if trace_adjusting then
        report_parbuilders("expanding font %a using step %a, shrink %a and stretch %a",f,step,stretch,shrink)
    end
    local e = expansions[f]
    checked_expansion[f] = e
    return e
end

local function check_expand_lines(checked_expansion,f)
    local expansion = parameters[f].expansion
    if not expansion then
        checked_expansion[f] = false
        return false
    end
-- expansion.step = 1
    local step    = expansion.step    or 0
    local stretch = expansion.stretch or 0
    local shrink  = expansion.shrink  or 0
    if step == 0 or (stretch == 0 and schrink == 0) then
        checked_expansion[f] = false
        return false
    end
    if trace_adjusting then
        report_parbuilders("expanding font %a using step %a, shrink %a and stretch %a",f,step,stretch,shrink)
    end
    local e = expansions[f]
    checked_expansion[f] = e
    return e
end

-- protrusion

local function find(head) -- do we really want to recurse into an hlist?
    while head do
        local id = head.id
        if id == glyph_code then
            return head
        elseif id == hlist_code then
            local found = find(head.list)
            if found then
                return found
            else
                head = head.next
            end
        elseif is_skipable(head) then
            head = head.next
        else
            return head
        end
    end
    return nil
end

local function find_protchar_left(l) -- weird function
    local ln = l.next
    if ln and ln.id == hlist_code and not ln.list and ln.width == 0 and ln.height == 0 and ln.depth == 0 then
        l = l.next
    else -- if d then -- was always true
        local id = l.id
        while ln and not (id == glyph_code or id < math_code) do -- is there always a glyph?
            l = ln
            ln = l.next
            id = ln.id
        end
    end
 -- if l.id == glyph_code then
 --     return l
 -- end
    return find(l) or l
end

local function find(head,tail)
    local tail = tail or slide_nodes(head)
    while tail do
        local id = tail.id
        if id == glyph_code then
            return tail
        elseif id == hlist_code then
            local found = find(tail.list)
            if found then
                return found
            else
                tail = tail.prev
            end
        elseif is_skipable(tail) then
            tail = tail.prev
        else
            return tail
        end
    end
    return nil
end

local function find_protchar_right(l,r)
    return r and find(l,r) or r
end

local function left_pw(p)
    local font = p.font
    local prot = chardata[font][p.char].left_protruding
    if not prot or prot == 0 then
        return 0
    end
    return prot * quaddata[font] / 1000, p
end

local function right_pw(p)
    local font = p.font
    local prot = chardata[font][p.char].right_protruding
    if not prot or prot == 0 then
        return 0
    end
    return prot * quaddata[font] / 1000, p
end

-- par parameters

local function reset_meta(par)
    local active = {
        id          = hyphenated_code,
        line_number = max_halfword,
    }
    active.next = par.active -- head of metalist
    par.active  = active
    par.passive = nil
end

local function add_to_width(line_break_dir,checked_expansion,s) -- split into two loops (normal and expansion)
    local size           = 0
    local adjust_stretch = 0
    local adjust_shrink  = 0
    while s do
        local id = s.id
        if id == glyph_code then
            if is_rotated[line_break_dir] then -- can be shared
                size = size + s.height + s.depth
            else
                size = size + s.width
            end
            if checked_expansion then
                local data = checked_expansion[s.font]
                if data then
                    data = data[s.char]
                    if data then
                        adjust_stretch = adjust_stretch + data.glyphstretch
                        adjust_shrink  = adjust_shrink  + data.glyphshrink
                    end
                end
            end
        elseif id == hlist_code or id == vlist_code then
            if is_parallel[s.dir][line_break_dir] then
                size = size + s.width
            else
                size = size + s.depth + s.height
            end
        elseif id == kern_code then
            local d = s.kern
            if d ~= 0 then 
                if checked_expansion and expand_kerns and (s.subtype == kerning_code or s[a_fontkern]) then
                    local stretch, shrink = kern_stretch_shrink(s,d)
                    if expand_kerns == "stretch" then
                        adjust_stretch = adjust_stretch + stretch
                    elseif expand_kerns == "shrink" then
                        adjust_shrink  = adjust_shrink  + shrink
                    else
                        adjust_stretch = adjust_stretch + stretch
                        adjust_shrink  = adjust_shrink  + shrink
                    end
                end
                size = size + d
            end
        elseif id == rule_code then
            size = size + s.width
        else
            report_parbuilders("unsupported node at location %a",6)
        end
        s = s.next
    end
    return size, adjust_stretch, adjust_shrink
end

local function compute_break_width(par,break_type,p) -- split in two
    local break_width = par.break_width
    if break_type > unhyphenated_code then
        local disc_width           = par.disc_width
        local checked_expansion    = par.checked_expansion
        local line_break_dir       = par.line_break_dir
        local break_size           = break_width.size           + disc_width.size
        local break_adjust_stretch = break_width.adjust_stretch + disc_width.adjust_stretch
        local break_adjust_shrink  = break_width.adjust_shrink  + disc_width.adjust_shrink
        local replace = p.replace
        if replace then
            local size, adjust_stretch, adjust_shrink = add_to_width(line_break_dir,checked_expansion,replace)
            break_size           = break_size           - size
            break_adjust_stretch = break_adjust_stretch - adjust_stretch
            break_adjust_shrink  = break_adjust_shrink  - adjust_shrink
        end
        local post = p.post
        if post then
            local size, adjust_stretch, adjust_shrink = add_to_width(line_break_dir,checked_expansion,post)
            break_size           = break_size           + size
            break_adjust_stretch = break_adjust_stretch + adjust_stretch
            break_adjust_shrink  = break_adjust_shrink  + adjust_shrink
        end
        break_width.size           = break_size
        break_width.adjust_stretch = break_adjust_stretch
        break_width.adjust_shrink  = break_adjust_shrink
        if not post then
            p = p.next
        else
            return
        end
    end
    while p do -- skip spacing etc
        local id = p.id
        if id == glyph_code then
            return -- happens often
        elseif id == glue_code then
            local spec = p.spec
            local order = stretch_orders[spec.stretch_order]
            break_width.size   = break_width.size   - spec.width
            break_width[order] = break_width[order] - spec.stretch
            break_width.shrink = break_width.shrink - spec.shrink
        elseif id == penalty_code then
            -- do nothing
        elseif id == kern_code then
            if p.subtype == userkern_code then
                break_width.size = break_width.size - p.kern
            else
                return
            end
        elseif id == math_code then
            break_width.size = break_width.size - p.surround
        else
            return
        end
        p = p.next
    end
end

local function append_to_vlist(par, b)
    local prev_depth = par.prev_depth
    if prev_depth > par.ignored_dimen then
        if b.id == hlist_code then
            local d = par.baseline_skip.width - prev_depth - b.height -- deficiency of space between baselines
            local s = d < par.line_skip_limit and new_lineskip(tex.lineskip) or new_baselineskip(d)
         -- local s = d < par.line_skip_limit
         -- if s then
         --     s = new_lineskip()
         --     s.spec = tex.lineskip
         -- else
         --     s = new_baselineskip(d)
         -- end
            local head_field = par.head_field
            if head_field then
                local n = slide_nodes(head_field)
                n.next = s
                s.prev = n
            else
                par.head_field = s
            end
        end
    end
    local head_field = par.head_field
    if head_field then
        local n = slide_nodes(head_field)
        n.next = b
        b.prev = n
    else
        par.head_field = b
    end
    if b.id == hlist_code then
        local pd = b.depth
        par.prev_depth = pd
        texnest[texnest.ptr].prevdepth = pd
    end
end

local function append_list(par, b)
    local head_field = par.head_field
    if head_field then
        local n = slide_nodes(head_field)
        n.next = b
        b.prev = n
    else
        par.head_field = b
    end
end

-- We can actually make par local to this module as we never break inside a break call and that way the
-- array is reused. At some point the information will be part of the paragraph spec as passed.

local hztolerance = 2500
local hzwarned    = false

local function initialize_line_break(head,display)

    local hang_indent    = tex.hangindent or 0
    local hsize          = tex.hsize or 0
    local hang_after     = tex.hangafter or 0
    local par_shape_ptr  = tex.parshape
    local left_skip      = tex.leftskip -- nodes
    local right_skip     = tex.rightskip -- nodes
    local pretolerance   = tex.pretolerance
    local tolerance      = tex.tolerance
    local adjust_spacing = tex.pdfadjustspacing
    local protrude_chars = tex.pdfprotrudechars
    local last_line_fit  = tex.lastlinefit

    local newhead = new_temp()
    newhead.next  = head

    local adjust_spacing_status = adjust_spacing > 1 and -1 or 0

    -- metatables

    local par = {
        head                         = newhead,
        head_field                   = nil,
        display                      = display,
        font_in_short_display        = 0,
        no_shrink_error_yet          = true,   -- have we complained about infinite shrinkage?
        second_pass                  = false,  -- is this our second attempt to break this paragraph?
        final_pass                   = false,  -- is this our final attempt to break this paragraph?
        threshold                    = 0,      -- maximum badness on feasible lines

        passive                      = nil,    -- most recent node on passive list
        printed_node                 = head,   -- most recent node that has been printed
        pass_number                  = 0,      -- the number of passive nodes allocated on this pass
        auto_breaking                = 0,      -- make auto_breaking accessible out of line_break

        active_width                 = { size = 0, stretch = 0, fi = 0, fil = 0, fill = 0, filll = 0, shrink = 0, adjust_stretch = 0, adjust_shrink = 0 },
        break_width                  = { size = 0, stretch = 0, fi = 0, fil = 0, fill = 0, filll = 0, shrink = 0, adjust_stretch = 0, adjust_shrink = 0 },
        disc_width                   = { size = 0,                                                                adjust_stretch = 0, adjust_shrink = 0 },
        fill_width                   = {           stretch = 0, fi = 0, fil = 0, fill = 0, filll = 0, shrink = 0                                        },
        background                   = { size = 0, stretch = 0, fi = 0, fil = 0, fill = 0, filll = 0, shrink = 0                                        },

        hang_indent                  = hang_indent,
        hsize                        = hsize,
        hang_after                   = hang_after,
        par_shape_ptr                = par_shape_ptr,
        left_skip                    = left_skip,
        right_skip                   = right_skip,
        pretolerance                 = pretolerance,
        tolerance                    = tolerance,

        protrude_chars               = protrude_chars,
        adjust_spacing               = adjust_spacing,
        max_stretch_ratio            = adjust_spacing_status,
        max_shrink_ratio             = adjust_spacing_status,
        cur_font_step                = adjust_spacing_status,
        checked_expansion            = false,
        tracing_paragraphs           = tex.tracingparagraphs > 0,

        emergency_stretch            = tex.emergencystretch     or 0,
        looseness                    = tex.looseness            or 0,
        line_penalty                 = tex.linepenalty          or 0,
        hyphen_penalty               = tex.hyphenpenalty        or 0,
        broken_penalty               = tex.brokenpenalty        or 0,
        inter_line_penalty           = tex.interlinepenalty     or 0,
        club_penalty                 = tex.clubpenalty          or 0,
        widow_penalty                = tex.widowpenalty         or 0,
        display_widow_penalty        = tex.displaywidowpenalty  or 0,
        ex_hyphen_penalty            = tex.exhyphenpenalty      or 0,

        adj_demerits                 = tex.adjdemerits          or 0,
        double_hyphen_demerits       = tex.doublehyphendemerits or 0,
        final_hyphen_demerits        = tex.finalhyphendemerits  or 0,

        first_line                   = 0, -- tex.nest[tex.nest.ptr].modeline, -- 0, -- cur_list.pg_field

        each_line_height             = tex.pdfeachlineheight    or 0, -- this will go away
        each_line_depth              = tex.pdfeachlinedepth     or 0, -- this will go away
        first_line_height            = tex.pdffirstlineheight   or 0, -- this will go away
        last_line_depth              = tex.pdflastlinedepth     or 0, -- this will go away
        ignored_dimen                = tex.pdfignoreddimen      or 0, -- this will go away

        baseline_skip                = tex.baselineskip         or 0,
        lineskip                     = tex.lineskip             or 0,
        line_skip_limit              = tex.lineskiplimit        or 0,

        prev_depth                   = texnest[texnest.ptr].prevdepth,

        final_par_glue               = slide_nodes(head), -- todo: we know tail already, slow

        par_break_dir                = tex.pardir,
        line_break_dir               = tex.pardir,

        internal_pen_inter           = 0,   -- running localinterlinepenalty
        internal_pen_broken          = 0,   -- running localbrokenpenalty
        internal_left_box            = nil, -- running localleftbox
        internal_left_box_width      = 0,   -- running localleftbox width
        init_internal_left_box       = nil, -- running localleftbox
        init_internal_left_box_width = 0,   -- running localleftbox width
        internal_right_box           = nil, -- running localrightbox
        internal_right_box_width     = 0,   -- running localrightbox width

        best_place                   = { }, -- how to achieve minimal_demerits
        best_pl_line                 = { }, -- corresponding line number
        easy_line                    = 0,   -- line numbers easy_line are equivalent in break nodes
        last_special_line            = 0,   -- line numbers last_special_line all have the same width
        first_width                  = 0,   -- the width of all lines last_special_line, if no parshape has been specified
        second_width                 = 0,   -- the width of all lines last_special_line
        first_indent                 = 0,   -- left margin to go with first_width
        second_indent                = 0,   -- left margin to go with second_width

        best_bet                     = nil, -- use this passive node and its predecessors
        fewest_demerits              = 0,   -- the demerits associated with best_bet
        best_line                    = 0,   -- line number following the last line of the new paragraph
        line_diff                    = 0,   -- the difference between the current line number and the optimum best_line

        -- not yet used

        best_pl_short                = { }, -- shortfall corresponding to minimal_demerits
        best_pl_glue                 = { }, -- corresponding glue stretch or shrink
        do_last_line_fit             = false,
        last_line_fit                = last_line_fit,

        minimum_demerits             = awful_badness,

        minimal_demerits             = {

            [fit_very_loose_class] = awful_badness,
            [fit_loose_class]      = awful_badness,
            [fit_decent_class]     = awful_badness,
            [fit_tight_class]      = awful_badness,

        },

        prev_char_p                  = nil,

        statistics                   = {

            noflines          = 0,
            nofprotrudedlines = 0,
            nofadjustedlines  = 0,

        },

     -- -- just a thought ... parshape functions ... it would be nice to
     -- -- also store the height so far (probably not too hard) although
     -- -- in most cases we work on grids in such cases
     --
     -- adapt_width = function(par,line)
     --     -- carry attribute, so that we can accumulate
     --     local left  = 655360 * (line - 1)
     --     local right = 655360 * (line - 1)
     --     return left, right
     -- end

    }

    if adjust_spacing > 1 then
        local checked_expansion = { par = par }
        setmetatableindex(checked_expansion,check_expand_pars)
        par.checked_expansion = checked_expansion

        if par.tolerance < hztolerance then
            if not hzwarned then
                report_parbuilders("setting tolerance to %a for hz",hztolerance)
                hzwarned = true
            end
            par.tolerance = hztolerance
        end

    end

    -- we need par for the error message

    local background = par.background

    local l = check_shrinkage(par,left_skip)
    local r = check_shrinkage(par,right_skip)
    local l_order = stretch_orders[l.stretch_order]
    local r_order = stretch_orders[r.stretch_order]

    background.size     = l.width + r.width
    background.shrink   = l.shrink + r.shrink
    background[l_order] = l.stretch
    background[r_order] = r.stretch + background[r_order]

    -- this will move up so that we can assign the whole par table

    if not par_shape_ptr then
        if hang_indent == 0 then
            par.second_width  = hsize
            par.second_indent = 0
        else
            local abs_hang_after  = hang_after >0 and hang_after  or -hang_after
            local abs_hang_indent = hang_indent>0 and hang_indent or -hang_indent
            par.last_special_line = abs_hang_after
            if hang_after < 0 then
                par.first_width = hsize - abs_hang_indent
                if hang_indent >= 0 then
                    par.first_indent = hang_indent
                else
                    par.first_indent = 0
                end
                par.second_width  = hsize
                par.second_indent = 0
            else
                par.first_width  = hsize
                par.first_indent = 0
                par.second_width = hsize - abs_hang_indent
                if hang_indent >= 0 then
                    par.second_indent = hang_indent
                else
                    par.second_indent = 0
                end
            end
        end
    else
        local last_special_line = #par_shape_ptr
        par.last_special_line = last_special_line
        local parshape = par_shape_ptr[last_special_line]
        par.second_width  = parshape[2]
        par.second_indent = parshape[1]
    end

    if par.looseness == 0 then
        par.easy_line = par.last_special_line
    else
        par.easy_line = max_halfword
    end

    if pretolerance >= 0 then
        par.threshold   = pretolerance
        par.second_pass = false
        par.final_pass  = false
    else
        par.threshold   = tolerance
        par.second_pass = true
        par.final_pass  = par.emergency_stretch <= 0
        if trace_basic then
            if par.final_pass then
                report_parbuilders("enabling second and final pass")
            else
                report_parbuilders("enabling second pass")
            end
        end
    end

    if last_line_fit > 0 then
        local spec          = par.final_par_glue.spec
        local stretch       = spec.stretch
        local stretch_order = spec.stretch_order
        if stretch > 0 and stretch_order > 0 and background.fi == 0 and background.fil == 0 and background.fill == 0 and background.filll == 0 then
            par.do_last_line_fit = true
            local si = stretch_orders[stretch_order]
            if trace_lastlinefit or trace_basic then
                report_parbuilders("enabling last line fit, stretch order %a set to %a, linefit is %a",si,stretch,last_line_fit)
            end
            par.fill_width[si] = stretch
        end
    end

    return par
end

local function post_line_break(par)

    local prevgraf       = texnest[texnest.ptr].prevgraf
    local cur_line       = prevgraf + 1 -- the current line number being justified
    local cur_p          = nil

    local adjust_spacing = par.adjust_spacing
    local protrude_chars = par.protrude_chars
    local statistics     = par.statistics

    local p, s, k, w  -- check when local

    local q = par.best_bet.break_node
    repeat -- goto first breakpoint
        local r = q
        q = q.prev_break
        r.prev_break = cur_p
        cur_p = r
    until not q

    local stack = new_dir_stack()

    repeat

        inject_dirs_at_begin_of_line(stack,par.head)

        local q = nil
        local r = cur_p.cur_break

        local disc_break      = false
        local post_disc_break = false
        local glue_break      = false

        if not r then
            r = slide_nodes(par.head)
            if r == par.final_par_glue then
                q = r      -- q refers to the last node of the line (and paragraph)
                r = r.prev -- r refers to the node after which the dir nodes should be closed
            end
        else
            local id = r.id
            if id == glue_code then
                -- r is normal skip
                r = replace_node(r,new_rightskip(par.right_skip))
                glue_break = true
                q = r      -- q refers to the last node of the line
                r = r.prev -- r refers to the node after which the dir nodes should be closed
            elseif id == disc_code then
                -- todo: use insert_before/after
                local prev_r  = r.prev
                local next_r  = r.next
                local subtype = r.subtype
                local pre     = r.pre
                local post    = r.post
                local replace = r.replace
                if subtype == second_disc_code then
                    if not (prev_r.id == disc_code and prev_r.subtype == first_disc_code) then
                        report_parbuilders('unsupported disc at location %a',3)
                    end
                    if pre then
                        flush_node_list(pre)
                        r.pre = nil
                        pre   = nil -- signal
                    end
                    if replace then
                        local n      = slide_nodes(replace)
                        prev_r.next  = replace
                        replace.prev = prev_r
                        n.next       = r
                        r.prev       = n
                        r.replace    = nil
                        replace      = nil -- signal
                    end
                    local pre     = prev_r.pre
                    local post    = prev_r.post
                    local replace = prev_r.replace
                    if pre then
                        flush_node_list(pre)
                        prev_r.pre = nil
                    end
                    if replace then
                        flush_node_list(replace)
                        prev_r.replace = nil
                    end
                    if post then
                        flush_node_list(post)
                        prev_r.post = nil
                    end
                elseif subtype == first_disc_code then
                    if not (v.id == disc_code and v.subtype == second_disc_code) then
                        report_parbuilders('unsupported disc at location %a',4)
                    end
                    next_r.subtype = regular_disc_code
                    next_r.replace = post
                    r.post         = nil
                end
                if replace then
                    r.replace = nil -- free
                    flush_node_list(replace)
                end
                if pre then
                    local n     = slide_nodes(pre)
                    prev_r.next = pre
                    pre.prev    = prev_r
                    n.next      = r
                    r.prev      = n
                    r.pre       = nil
                end
                if post then
                    local n         = slide_nodes(post)
                    r.next          = post
                    post.prev       = r
                    n.next          = next_r
                    next_r.prev     = n
                    r.post          = nil
                    post_disc_break = true
                end
                disc_break = true
            elseif id == kern_code then
                r.kern = 0
            elseif r.id == math_code then
                r.surround = 0
            end
        end
        r = inject_dirs_at_end_of_line(stack,r,par.head.next,cur_p.cur_break)
        local crb  = cur_p.passive_right_box
        if crb then
            local s = copy_node(crb)
            local e = r.next
            r.next = s
            s.prev = r
            s.next = e
            if e then
                e.prev = s
            end
            r = s
        end
        if not q then
            q = r
        end
        if q and q ~= par.head and protrude_chars > 0 then
            local id = q.id
            local c = (disc_break and (id == glyph_code or id ~= disc_code) and q) or q.prev
            local p = find_protchar_right(par.head.next,c)
            if p and p.id == glyph_code then
                local w, last_rightmost_char = right_pw(p)
                if last_rightmost_char and w ~= 0 then
                    -- so we inherit attributes, q is new pseudo head
                    q, c = insert_node_after(q,c,new_rightmarginkern(copy_node(last_rightmost_char),-w))
                end
            end
        end
        if not glue_break then
            local h
            h, q = insert_node_after(q,q,new_rightskip(par.right_skip)) -- q moves on as pseudo head
        end
        r           = q.next
        q.next      = nil
        local phead = par.head
        q           = phead.next
        phead.next  = r
        if r then
            r.prev = phead
        end
        local clb  = cur_p.passive_left_box
        if clb then -- here we miss some prev links
            local s = copy_node(cb)
            s       = q.next
            r.next  = q
            q       = r
            if s and cur_line == (par.first_line + 1) and s.id == hlist_code and not s.list then
                q      = q.next
                r.next = s.next
                s.next = r
            end
        end
        if protrude_chars > 0 then
            local p = find_protchar_left(q)
            if p and p.id == glyph_code then
                local w, last_leftmost_char = left_pw(p)
                if last_leftmost_char and w ~= 0 then
                    -- so we inherit attributes, q is pseudo head and moves back
                    q = insert_node_before(q,q,new_leftmarginkern(copy_node(last_leftmost_char),-w))
                end
            end
        end
        local ls = par.left_skip
        if ls and (ls.width ~= 0 or ls.stretch ~= 0 or ls.shrink ~= 0) then
            q = insert_node_before(q,q,new_leftskip(ls))
        end
        local curwidth, cur_indent
        if cur_line > par.last_special_line then
            cur_indent = par.second_indent
            cur_width  = par.second_width
        else
            local psp = par.par_shape_ptr
            if psp then
                cur_indent = psp[cur_line][1]
                cur_width  = psp[cur_line][2]
            else
                cur_indent = par.first_indent
                cur_width  = par.first_width
            end
        end
        statistics.noflines = statistics.noflines + 1
        if adjust_spacing > 0 then
            statistics.nofadjustedlines = statistics.nofadjustedlines + 1
            -- in the built-in hpack cal_expand_ratio will later on call subst_ext_font
            -- in the alternative approach we can do both in one run
            just_box = xpack_nodes(q,cur_width,"cal_expand_ratio",par.par_break_dir) -- ,cur_p.analysis)
        else
            just_box = xpack_nodes(q,cur_width,"exactly",par.par_break_dir) -- ,cur_p.analysis)
        end
        if protrude_chars > 0 then
            statistics.nofprotrudedlines = statistics.nofprotrudedlines + 1
        end
        -- wrong:
        local adjust_head     = texlists.adjust_head
        local pre_adjust_head = texlists.pre_adjust_head
        --
        just_box.shift = cur_indent
        if par.each_line_height ~= par.ignored_dimen then
            just_box.height = par.each_line_height
        end
        if par.each_line_depth ~= par.ignored_dimen then
            just_box.depth = par.each_line_depth
        end
        if par.first_line_height ~= par.ignored_dimen and (cur_line == par.first_line + 1) then
            just_box.height = par.first_line_height
        end
        if par.last_line_depth ~= par.ignored_dimen and cur_line + 1 == par.best_line then
            just_box.depth = par.last_line_depth
        end
        if texlists.pre_adjust_head ~= pre_adjust_head then
            append_list(par, texlists.pre_adjust_head)
            texlists.pre_adjust_head = pre_adjust_head
        end
        append_to_vlist(par, just_box)
        if texlists.adjust_head ~= adjust_head then
            append_list(par, texlists.adjust_head)
            texlists.adjust_head = adjust_head
        end
        local pen
        if cur_line + 1 ~= par.best_line then
            if cur_p.passive_pen_inter then
                pen = cur_p.passive_pen_inter
            else
                pen = par.inter_line_penalty
            end
            if cur_line == prevgraf + 1 then
                pen = pen + par.club_penalty
            end
            if cur_line + 2 == par.best_line then
                if par.display then
                    pen = pen + par.display_widow_penalty
                else
                    pen = pen + par.widow_penalty
                end
            end
            if disc_break then
                if cur_p.passive_pen_broken ~= 0 then
                    pen = pen + cur_p.passive_pen_broken
                else
                    pen = pen + par.broken_penalty
                end
            end
            if pen ~= 0 then
                append_to_vlist(par,new_penalty(pen))
             end
        end
        cur_line = cur_line + 1
        cur_p = cur_p.prev_break
        if cur_p and not post_disc_break then
            local phead = par.head
            local r = phead
            while true do
                q = r.next
                if q == cur_p.cur_break or q.id == glyph_code then
                    break
                end
                local id = q.id
                if not (id == whatsit_code and q.subtype == localpar_code) then
                    if id < math_code or (id == kern_code and q.subtype ~= userkern_code) then
                        break
                    end
                end
                r = q
            end
            if r ~= phead then
                r.next = nil
                flush_node_list(phead.next)
                phead.next = q
                if q then
                    q.prev = phead
                end
            end
        end
    until not cur_p
    if cur_line ~= par.best_line then -- or not par.head.next then
        report_parbuilders("line breaking")
    end
    if par.head then -- added
--         flush_node(par.head) -- the localpar_code whatsit
        par.head = nil
    end
    cur_line = cur_line - 1
    if trace_basic then
        report_parbuilders("paragraph broken into %a lines",cur_line)
    end
    texnest[texnest.ptr].prevgraf  = cur_line
end

local function wrap_up(par)
    if par.tracing_paragraphs then
        diagnostics.stop()
    end
    if par.do_last_line_fit then
        local best_bet     = par.best_bet
        local active_short = best_bet.active_short
        local active_glue  = best_bet.active_glue
        if active_short == 0 then
            if trace_lastlinefit then
                report_parbuilders("disabling last line fit, no active_short")
            end
            par.do_last_line_fit = false
        else
            local glue = par.final_par_glue
            local spec = copy_node(glue.spec)
            spec.width = spec.width + active_short - active_glue
            spec.stretch = 0
        --  flush_node(glue.spec) -- brrr, when we do this we can get an "invalid id stretch message", maybe dec refcount
            glue.spec = spec
            if trace_lastlinefit then
                report_parbuilders("applying last line fit, short %a, glue %p",active_short,active_glue)
            end
        end
    end
    -- we have a bunch of glue and and temp nodes not freed
    local head = par.head
    if head.id == temp_code then
        par.head = head.next
        flush_node(head)
    end
    post_line_break(par)
    reset_meta(par)
    register_statistics(par)
    return par.head_field
end

-- we could do active nodes differently ... table instead of linked list or a list
-- with prev nodes

local function deactivate_node(par,prev_prev_r,prev_r,r,cur_active_width,checked_expansion) -- no need for adjust if disabled
    local active = par.active
    local active_width = par.active_width
    prev_r.next = r.next
    -- removes r
    -- r = nil
    if prev_r == active then
        r = active.next
        if r.id == delta_code then
            local aw = active_width.size    + r.size    active_width.size    = aw  cur_active_width.size    = aw
            local aw = active_width.stretch + r.stretch active_width.stretch = aw  cur_active_width.stretch = aw
            local aw = active_width.fi      + r.fi      active_width.fi      = aw  cur_active_width.fi      = aw
            local aw = active_width.fil     + r.fil     active_width.fil     = aw  cur_active_width.fil     = aw
            local aw = active_width.fill    + r.fill    active_width.fill    = aw  cur_active_width.fill    = aw
            local aw = active_width.filll   + r.filll   active_width.filll   = aw  cur_active_width.filll   = aw
            local aw = active_width.shrink  + r.shrink  active_width.shrink  = aw  cur_active_width.shrink  = aw
            if checked_expansion then
                local aw = active_width.adjust_stretch + r.adjust_stretch  active_width.adjust_stretch = aw  cur_active_width.adjust_stretch = aw
                local aw = active_width.adjust_shrink  + r.adjust_shrink   active_width.adjust_shrink  = aw  cur_active_width.adjust_shrink  = aw
            end
            active.next = r.next
            -- removes r
            -- r = nil
        end
    elseif prev_r.id == delta_code then
        r = prev_r.next
        if r == active then
            cur_active_width.size    = cur_active_width.size    - prev_r.size
            cur_active_width.stretch = cur_active_width.stretch - prev_r.stretch
            cur_active_width.fi      = cur_active_width.fi      - prev_r.fi
            cur_active_width.fil     = cur_active_width.fil     - prev_r.fil
            cur_active_width.fill    = cur_active_width.fill    - prev_r.fill
            cur_active_width.filll   = cur_active_width.filll   - prev_r.filll
            cur_active_width.shrink  = cur_active_width.shrink  - prev_r.shrink
            if checked_expansion then
                cur_active_width.adjust_stretch = cur_active_width.adjust_stretch - prev_r.adjust_stretch
                cur_active_width.adjust_shrink  = cur_active_width.adjust_shrink  - prev_r.adjust_shrink
            end
            prev_prev_r.next = active
            -- removes prev_r
            -- prev_r = nil
            prev_r = prev_prev_r
        elseif r.id == delta_code then
            local rn = r.size     cur_active_width.size    = cur_active_width.size    + rn  prev_r.size    = prev_r.size    + rn
            local rn = r.stretch  cur_active_width.stretch = cur_active_width.stretch + rn  prev_r.stretch = prev_r.stretch + rn
            local rn = r.fi       cur_active_width.fi      = cur_active_width.fi      + rn  prev_r.fi      = prev_r.fi      + rn
            local rn = r.fil      cur_active_width.fil     = cur_active_width.fil     + rn  prev_r.fil     = prev_r.fil     + rn
            local rn = r.fill     cur_active_width.fill    = cur_active_width.fill    + rn  prev_r.fill    = prev_r.fill    + rn
            local rn = r.filll    cur_active_width.filll   = cur_active_width.filll   + rn  prev_r.filll   = prev_r.fill    + rn
            local rn = r.shrink   cur_active_width.shrink  = cur_active_width.shrink  + rn  prev_r.shrink  = prev_r.shrink  + rn
            if checked_expansion then
                local rn = r.adjust_stretch  cur_active_width.adjust_stretch = cur_active_width.adjust_stretch + rn  prev_r.adjust_stretch = prev_r.adjust_stretch    + rn
                local rn = r.adjust_shrink   cur_active_width.adjust_shrink  = cur_active_width.adjust_shrink  + rn  prev_r.adjust_shrink  = prev_r.adjust_shrink     + rn
            end
            prev_r.next = r.next
            -- removes r
            -- r = nil
        end
    end
    return prev_r, r
end

local function lastlinecrap(shortfall,active_short,active_glue,cur_active_width,fill_width,last_line_fit)
    if active_short == 0 or active_glue <= 0 then
        return false, 0, fit_decent_class, 0, 0
    end
    if cur_active_width.fi ~= fill_width.fi or cur_active_width.fil ~= fill_width.fil or cur_active_width.fill ~= fill_width.fill or cur_active_width.filll ~= fill_width.filll then
        return false, 0, fit_decent_class, 0, 0
    end
    local adjustment = active_short > 0 and cur_active_width.stretch or cur_active_width.shrink
    if adjustment <= 0 then
        return false, 0, fit_decent_class, adjustment, 0
    end
    adjustment = calculate_fraction(adjustment,active_short,active_glue,maxdimen)
    if last_line_fit < 1000 then
        adjustment = calculate_fraction(adjustment,last_line_fit,1000,maxdimen) -- uses previous adjustment
    end
    local fit_class = fit_decent_class
    if adjustment > 0 then
        local stretch = cur_active_width.stretch
        if adjustment > shortfall then
            adjustment = shortfall
        end
        if adjustment > 7230584 and stretch < 1663497 then
            return true, fit_very_loose_class, shortfall, adjustment, infinite_badness
        end
     -- if adjustment == 0 then -- badness = 0
     --     return true, shortfall, fit_decent_class, 0, 0
     -- elseif stretch <= 0 then -- badness = 10000
     --     return true, shortfall, fit_very_loose_class, adjustment, 10000
     -- end
     -- local badness = (adjustment == 0 and 0) or (stretch <= 0 and 10000) or calculate_badness(adjustment,stretch)
        local badness = calculate_badness(adjustment,stretch)
        if badness > 99 then
            return true, shortfall, fit_very_loose_class, adjustment, badness
        elseif badness > 12 then
            return true, shortfall, fit_loose_class, adjustment, badness
        else
            return true, shortfall, fit_decent_class, adjustment, badness
        end
    elseif adjustment < 0 then
        local shrink = cur_active_width.shrink
        if -adjustment > shrink then
            adjustment = -shrink
        end
        local badness = calculate_badness(-adjustment,shrink)
        if badness > 12 then
            return true, shortfall, fit_tight_class, adjustment, badness
        else
            return true, shortfall, fit_decent_class, adjustment, badness
        end
    else
        return false, 0, fit_decent_class, 0, 0
    end
end

local function try_break(pi, break_type, par, first_p, cur_p, checked_expansion)

    if pi >= infinite_penalty then
        return                              -- this breakpoint is inhibited by infinite penalty
    elseif pi <= -infinite_penalty then
        pi = eject_penalty                  -- this breakpoint will be forced
    end

    local prev_prev_r         = nil         -- a step behind prev_r, if type(prev_r)=delta_code
    local prev_r              = par.active  -- stays a step behind r
    local r                   = nil         -- runs through the active list
    local no_break_yet        = true        -- have we found a feasible break at cur_p?
    local node_r_stays_active = false       -- should node r remain in the active list?
    local line_width          = 0           -- the current line will be justified to this width
    local line_number         = 0           -- line number of current active node
    local old_line_number     = 0           -- maximum line number in current equivalence class of lines

    local protrude_chars      = par.protrude_chars
    local checked_expansion   = par.checked_expansion
    local break_width         = par.break_width
    local active_width        = par.active_width
    local background          = par.background
    local minimal_demerits    = par.minimal_demerits
    local best_place          = par.best_place
    local best_pl_line        = par.best_pl_line
    local best_pl_short       = par.best_pl_short
    local best_pl_glue        = par.best_pl_glue
    local do_last_line_fit    = par.do_last_line_fit
    local final_pass          = par.final_pass
    local tracing_paragraphs  = par.tracing_paragraphs
 -- local par_active          = par.active

    local cur_active_width = checked_expansion and { -- distance from current active node
        size           = active_width.size,
        stretch        = active_width.stretch,
        fi             = active_width.fi,
        fil            = active_width.fil,
        fill           = active_width.fill,
        filll          = active_width.filll,
        shrink         = active_width.shrink,
        adjust_stretch = active_width.adjust_stretch,
        adjust_shrink  = active_width.adjust_shrink,
    } or {
        size           = active_width.size,
        stretch        = active_width.stretch,
        fi             = active_width.fi,
        fil            = active_width.fil,
        fill           = active_width.fill,
        filll          = active_width.filll,
        shrink         = active_width.shrink,
    }

    while true do
        r = prev_r.next
        if r.id == delta_code then
            cur_active_width.size    = cur_active_width.size    + r.size
            cur_active_width.stretch = cur_active_width.stretch + r.stretch
            cur_active_width.fi      = cur_active_width.fi      + r.fi
            cur_active_width.fil     = cur_active_width.fil     + r.fil
            cur_active_width.fill    = cur_active_width.fill    + r.fill
            cur_active_width.filll   = cur_active_width.filll   + r.filll
            cur_active_width.shrink  = cur_active_width.shrink  + r.shrink
            if checked_expansion then
                cur_active_width.adjust_stretch = cur_active_width.adjust_stretch + r.adjust_stretch
                cur_active_width.adjust_shrink  = cur_active_width.adjust_shrink  + r.adjust_shrink
            end
            prev_prev_r = prev_r
            prev_r = r
        else
            line_number = r.line_number
            if line_number > old_line_number then
                local minimum_demerits = par.minimum_demerits
                if minimum_demerits < awful_badness and (old_line_number ~= par.easy_line or r == par.active) then
                    if no_break_yet then
                        no_break_yet = false
                        break_width.size    = background.size
                        break_width.stretch = background.stretch
                        break_width.fi      = background.fi
                        break_width.fil     = background.fil
                        break_width.fill    = background.fill
                        break_width.filll   = background.filll
                        break_width.shrink  = background.shrink
                        if checked_expansion then
                            break_width.adjust_stretch = 0
                            break_width.adjust_shrink  = 0
                        end
                        if cur_p then
                            compute_break_width(par,break_type,cur_p)
                        end
                    end
                    if prev_r.id == delta_code then
                        prev_r.size    = prev_r.size    - cur_active_width.size   + break_width.size
                        prev_r.stretch = prev_r.stretch - cur_active_width.stretc + break_width.stretch
                        prev_r.fi      = prev_r.fi      - cur_active_width.fi     + break_width.fi
                        prev_r.fil     = prev_r.fil     - cur_active_width.fil    + break_width.fil
                        prev_r.fill    = prev_r.fill    - cur_active_width.fill   + break_width.fill
                        prev_r.filll   = prev_r.filll   - cur_active_width.filll  + break_width.filll
                        prev_r.shrink  = prev_r.shrink  - cur_active_width.shrink + break_width.shrink
                        if checked_expansion then
                            prev_r.adjust_stretch = prev_r.adjust_stretch - cur_active_width.adjust_stretch + break_width.adjust_stretch
                            prev_r.adjust_shrink  = prev_r.adjust_shrink  - cur_active_width.adjust_shrink  + break_width.adjust_shrink
                        end
                    elseif prev_r == par.active then
                        active_width.size    = break_width.size
                        active_width.stretch = break_width.stretch
                        active_width.fi      = break_width.fi
                        active_width.fil     = break_width.fil
                        active_width.fill    = break_width.fill
                        active_width.filll   = break_width.filll
                        active_width.shrink  = break_width.shrink
                        if checked_expansion then
                            active_width.adjust_stretch = break_width.adjust_stretch
                            active_width.adjust_shrink  = break_width.adjust_shrink
                        end
                    else
                        local q = checked_expansion and {
                            id             = delta_code,
                            subtype        = nosubtype_code,
                            next           = r,
                            size           = break_width.size           - cur_active_width.size,
                            stretch        = break_width.stretch        - cur_active_width.stretch,
                            fi             = break_width.fi             - cur_active_width.fi,
                            fil            = break_width.fil            - cur_active_width.fil,
                            fill           = break_width.fill           - cur_active_width.fill,
                            filll          = break_width.filll          - cur_active_width.filll,
                            shrink         = break_width.shrink         - cur_active_width.shrink,
                            adjust_stretch = break_width.adjust_stretch - cur_active_width.adjust_stretch,
                            adjust_shrink  = break_width.adjust_shrink  - cur_active_width.adjust_shrink,
                        } or {
                            id             = delta_code,
                            subtype        = nosubtype_code,
                            next           = r,
                            size           = break_width.size           - cur_active_width.size,
                            stretch        = break_width.stretch        - cur_active_width.stretch,
                            fi             = break_width.fi             - cur_active_width.fi,
                            fil            = break_width.fil            - cur_active_width.fil,
                            fill           = break_width.fill           - cur_active_width.fill,
                            filll          = break_width.filll          - cur_active_width.filll,
                            shrink         = break_width.shrink         - cur_active_width.shrink,
                        }
                        prev_r.next = q
                        prev_prev_r = prev_r
                        prev_r = q
                    end
                    local adj_demerits     = par.adj_demerits
                    local abs_adj_demerits = adj_demerits > 0 and adj_demerits or -adj_demerits
                    if abs_adj_demerits >= awful_badness - minimum_demerits then
                        minimum_demerits = awful_badness - 1
                    else
                        minimum_demerits = minimum_demerits + abs_adj_demerits
                    end
                    for fit_class = fit_very_loose_class, fit_tight_class do
                        if minimal_demerits[fit_class] <= minimum_demerits then
                            -- insert a new active node from best_place[fit_class] to cur_p
                            par.pass_number = par.pass_number + 1
                            local prev_break = best_place[fit_class]
                            local passive = {
                                id                          = passive_code,
                                subtype                     = nosubtype_code,
                                next                        = par.passive,
                                cur_break                   = cur_p,
                                serial                      = par.pass_number,
                                prev_break                  = prev_break,
                                passive_pen_inter           = par.internal_pen_inter,
                                passive_pen_broken          = par.internal_pen_broken,
                                passive_last_left_box       = par.internal_left_box,
                                passive_last_left_box_width = par.internal_left_box_width,
                                passive_left_box            = prev_break and prev_break.passive_last_left_box or par.init_internal_left_box,
                                passive_left_box_width      = prev_break and prev_break.passive_last_left_box_width or par.init_internal_left_box_width,
                                passive_right_box           = par.internal_right_box,
                                passive_right_box_width     = par.internal_right_box_width,
-- analysis = table.fastcopy(cur_active_width),
                            }
                            par.passive = passive
                            local q = {
                                id             = break_type,
                                subtype        = fit_class,
                                break_node     = passive,
                                line_number    = best_pl_line[fit_class] + 1,
                                total_demerits = minimal_demerits[fit_class], --  or 0,
                                next           = r,
                            }
                            if do_last_line_fit then
                                local active_short = best_pl_short[fit_class]
                                local active_glue  = best_pl_glue[fit_class]
                                q.active_short = active_short
                                q.active_glue  = active_glue
                                if trace_lastlinefit then
                                    report_parbuilders("setting short to %i and glue to %p using class %a",active_short,active_glue,fit_class)
                                end
                            end
                         -- q.next = r -- already done
                            prev_r.next = q
                            prev_r = q
                            if tracing_paragraphs then
                                diagnostics.break_node(par,q,fit_class,break_type,cur_p)
                            end
                        end
                        minimal_demerits[fit_class] = awful_badness
                    end
                    par.minimum_demerits = awful_badness
                    if r ~= par.active then
                        local q = checked_expansion and {
                            id             = delta_code,
                            subtype        = nosubtype_code,
                            next           = r,
                            size           = cur_active_width.size           - break_width.size,
                            stretch        = cur_active_width.stretch        - break_width.stretch,
                            fi             = cur_active_width.fi             - break_width.fi,
                            fil            = cur_active_width.fil            - break_width.fil,
                            fill           = cur_active_width.fill           - break_width.fill,
                            filll          = cur_active_width.filll          - break_width.filll,
                            shrink         = cur_active_width.shrink         - break_width.shrink,
                            adjust_stretch = cur_active_width.adjust_stretch - break_width.adjust_stretch,
                            adjust_shrink  = cur_active_width.adjust_shrink  - break_width.adjust_shrink,
                        } or {
                            id             = delta_code,
                            subtype        = nosubtype_code,
                            next           = r,
                            size           = cur_active_width.size           - break_width.size,
                            stretch        = cur_active_width.stretch        - break_width.stretch,
                            fi             = cur_active_width.fi             - break_width.fi,
                            fil            = cur_active_width.fil            - break_width.fil,
                            fill           = cur_active_width.fill           - break_width.fill,
                            filll          = cur_active_width.filll          - break_width.filll,
                            shrink         = cur_active_width.shrink         - break_width.shrink,
                        }
                     -- q.next = r -- already done
                        prev_r.next = q
                        prev_prev_r = prev_r
                        prev_r = q
                    end
                end
                if r == par.active then
                    return
                end
                if line_number > par.easy_line then
                    old_line_number = max_halfword - 1
                    line_width = par.second_width
                else
                    old_line_number = line_number
                    if line_number > par.last_special_line then
                        line_width = par.second_width
                    elseif par.par_shape_ptr then
                        line_width = par.par_shape_ptr[line_number][2]
                    else
                        line_width = par.first_width
                    end
                end
            end
            local artificial_demerits = false -- has d been forced to zero
            local shortfall = line_width - cur_active_width.size - par.internal_right_box_width -- used in badness calculations
            if not r.break_node then
                shortfall = shortfall - par.init_internal_left_box_width
            else
                shortfall = shortfall - (r.break_node.passive_last_left_box_width or 0)
            end
            local pw, lp, rp -- used later on
            if protrude_chars > 1 then
                -- this is quite time consuming
                local b = r.break_node
                local l = b and b.cur_break or first_p
                local o = cur_p and cur_p.prev
                if cur_p and cur_p.id == disc_code and cur_p.pre then
                    o = slide_nodes(cur_p.pre)
                else
                    o = find_protchar_right(l,o)
                end
                if o and o.id == glyph_code then
                    pw, rp = right_pw(o)
                    shortfall = shortfall + pw
                end
                local id = l.id
                if id == glyph_code then
                    -- ok ?
                elseif id == disc_code and l.post then
                    l = l.post -- TODO: first char could be a disc
                else
                    l = find_protchar_left(l)
                end
                if l and l.id == glyph_code then
                    pw, lp = left_pw(l)
                    shortfall = shortfall + pw
                end
            end
            if checked_expansion and shortfall ~= 0 then
                local margin_kern_stretch = 0
                local margin_kern_shrink  = 0
                if protrude_chars > 1 then
                    if lp then
--                         margin_kern_stretch, margin_kern_shrink = cal_margin_kern_var(lp)
local data = expansions[lp.font][lp.char]
if data then
    margin_kern_stretch, margin_kern_shrink = data.glyphstretch, data.glyphshrink
end
                    end
                    if rp then
--                         local mka, mkb = cal_margin_kern_var(rp)
--                         margin_kern_stretch = margin_kern_stretch + mka
--                         margin_kern_shrink  = margin_kern_shrink  + mkb
local data = expansions[lp.font][lp.char]
if data then
    margin_kern_stretch = margin_kern_stretch + data.glyphstretch
    margin_kern_shrink  = margin_kern_shrink  + data.glyphshrink
end
                    end
                end
                local total = cur_active_width.adjust_stretch + margin_kern_stretch
                if shortfall > 0 and total > 0 then
                    if total > shortfall then
                        shortfall = total / (par.max_stretch_ratio / par.cur_font_step) / 2 -- to be adapted
                    else
                        shortfall = shortfall - total
                    end
                else
                    total = cur_active_width.adjust_shrink + margin_kern_shrink
                    if shortfall < 0 and total > 0 then
                        if total > - shortfall then
                            shortfall = - total / (par.max_shrink_ratio / par.cur_font_step) / 2 -- to be adapted
                        else
                            shortfall = shortfall + total
                        end
                    end
                end
            end
            local b = 0
            local g = 0
            local fit_class = fit_decent_class
            local found = false
            if shortfall > 0  then
                if cur_active_width.fi ~= 0 or cur_active_width.fil ~= 0 or cur_active_width.fill ~= 0 or cur_active_width.filll ~= 0 then
                    if not do_last_line_fit then
                        -- okay
                    elseif not cur_p then
                        found, shortfall, fit_class, g, b = lastlinecrap(shortfall,r.active_short,r.active_glue,cur_active_width,par.fill_width,par.last_line_fit)
                    else
                        shortfall = 0
                    end
                else
                    local stretch = cur_active_width.stretch
                    if shortfall > 7230584 and stretch < 1663497 then
                        b = infinite_badness
                        fit_class = fit_very_loose_class
                    else
                        b = calculate_badness(shortfall,stretch)
                        if b > 99 then
                            fit_class = fit_very_loose_class
                        elseif b > 12 then
                            fit_class = fit_loose_class
                        else
                            fit_class = fit_decent_class
                        end
                    end
                end
            else
                local shrink = cur_active_width.shrink
                if -shortfall > shrink then
                    b = infinite_badness + 1
                else
                    b = calculate_badness(-shortfall,shrink)
                end
                if b > 12 then
                    fit_class = fit_tight_class
                else
                    fit_class = fit_decent_class
                end
            end
            if do_last_line_fit and not found then
                if not cur_p then
                 -- g = 0
                    shortfall = 0
                elseif shortfall > 0 then
                    g = cur_active_width.stretch
                elseif shortfall < 0 then
                    g = cur_active_width.shrink
                else
                    g = 0
                end
            end
            -- ::FOUND::
            local continue_only = false -- brrr
            if b > infinite_badness or pi == eject_penalty then
                if final_pass and par.minimum_demerits == awful_badness and r.next == par.active and prev_r == par.active then
                    artificial_demerits = true -- set demerits zero, this break is forced
                    node_r_stays_active = false
                elseif b > par.threshold then
                    prev_r, r = deactivate_node(par,prev_prev_r,prev_r,r,cur_active_width,checked_expansion)
                    continue_only = true
                else
                    node_r_stays_active = false
                end
            else
                prev_r = r
                if b > par.threshold then
                    continue_only = true
                else
                    node_r_stays_active = true
                end
            end
            if not continue_only then
                local d = 0
                if not artificial_demerits then
                    d = par.line_penalty + b
                    if (d >= 0 and d or -d) >= 10000 then -- abs(d)
                        d = 100000000
                    else
                        d = d * d
                    end
                    if pi == 0 then
                        -- nothing
                    elseif pi > 0 then
                        d = d + pi * pi
                    elseif pi > eject_penalty then
                        d = d - pi * pi
                    end
                    if break_type == hyphenated_code and r.id == hyphenated_code then
                        if cur_p then
                            d = d + par.double_hyphen_demerits
                        else
                            d = d + par.final_hyphen_demerits
                        end
                    end
                    local delta = fit_class - r.subtype
                    if (delta >= 0 and delta or -delta) > 1 then -- abs(delta)
                        d = d + par.adj_demerits
                    end
                end
                if tracing_paragraphs then
                    diagnostics.feasible_break(par,cur_p,r,b,pi,d,artificial_demerits)
                end
                d = d + r.total_demerits -- this is the minimum total demerits from the beginning to cur_p via r
                if d <= minimal_demerits[fit_class] then
                    minimal_demerits[fit_class] = d
                    best_place      [fit_class] = r.break_node
                    best_pl_line    [fit_class] = line_number
                    if do_last_line_fit then
                        best_pl_short[fit_class] = shortfall
                        best_pl_glue [fit_class] = g
                        if trace_lastlinefit then
                            report_parbuilders("storing last line fit short %a and glue %p in class %a",shortfall,g,fit_class)
                        end
                    end
                    if d < par.minimum_demerits then
                        par.minimum_demerits = d
                    end
                end
                if not node_r_stays_active then
                    prev_r, r = deactivate_node(par,prev_prev_r,prev_r,r,cur_active_width,checked_expansion)
                end
            end
        end
    end
end

local function kern_break(par, cur_p, first_p, checked_expansion) -- move inline if needed
    local v = cur_p.next
    if par.auto_breaking and v.id == glue_code then
        try_break(0, unhyphenated_code, par, first_p, cur_p, checked_expansion)
    end
    local active_width = par.active_width
    if cur_p.id ~= math_code then
        active_width.size = active_width.size + cur_p.kern
    else
        active_width.size = active_width.size + cur_p.surround
    end
end

-- we can call the normal one for simple box building in the otr so we need
-- frequent enabling/disabling

local temp_head = new_temp()

function constructors.methods.basic(head,d)
    if trace_basic then
        report_parbuilders("starting at %a",head)
    end

    local par = initialize_line_break(head,d)

    local checked_expansion  = par.checked_expansion
    local active_width       = par.active_width
    local disc_width         = par.disc_width
    local background         = par.background
    local tracing_paragraphs = par.tracing_paragraphs

    local dirstack = new_dir_stack()

    if tracing_paragraphs then
        diagnostics.start()
        if par.pretolerance >= 0 then
            diagnostics.current_pass(par,"firstpass")
        end
    end

    while true do
        reset_meta(par)
        if par.threshold > infinite_badness then
            par.threshold = infinite_badness
        end
        par.active.next = {
            id             = unhyphenated_code,
            subtype        = fit_decent_class,
            next           = par.active,
            break_node     = nil,
            line_number    = par.first_line + 1,
            total_demerits = 0,
            active_short   = 0,
            active_glue    = 0,
        }
        active_width.size           = background.size
        active_width.stretch        = background.stretch
        active_width.fi             = background.fi
        active_width.fil            = background.fil
        active_width.fill           = background.fill
        active_width.filll          = background.filll
        active_width.shrink         = background.shrink

        if checked_expansion then
            active_width.adjust_stretch = 0
            active_width.adjust_shrink  = 0
        end

        par.passive                 = nil -- = 0
        par.printed_node            = temp_head -- only when tracing, shared
        par.printed_node.next       = head
        par.pass_number             = 0
        par.auto_breaking           = true

        local cur_p                 = head
        local first_p               = cur_p

        par.font_in_short_display   = 0

        if cur_p and cur_p.id == whatsit_code and cur_p.subtype == localpar_code then
            par.init_internal_left_box       = cur_p.box_left
            par.init_internal_left_box_width = cur_p.box_left_width
            par.internal_pen_inter           = cur_p.pen_inter
            par.internal_pen_broken          = cur_p.pen_broken
            par.internal_left_box            = par.init_internal_left_box
            par.internal_left_box_width      = par.init_internal_left_box_width
            par.internal_right_box           = cur_p.box_right
            par.internal_right_box_width     = cur_p.box_right_width
        end

        -- all passes are combined in this loop so maybe we should split this into
        -- three function calls; we then also need to do the wrap_up elsewhere

        -- split into normal and expansion loop

        -- use an active local

        local fontexp, lastfont -- we can pass fontexp to calculate width if needed

        while cur_p and par.active.next ~= par.active do
            while cur_p and cur_p.id == glyph_code do
                if is_rotated[par.line_break_dir] then
                    active_width.size = active_width.size + cur_p.height + cur_p.depth
                else
                    active_width.size = active_width.size + cur_p.width
                end
                if checked_expansion then
                    local data= checked_expansion[cur_p.font]
                    if data then
                        local currentfont = cur_p.font
                        if currentfont ~= lastfont then
                            fontexps = checked_expansion[currentfont] -- a bit redundant for the par line packer
                            lastfont = currentfont
                        end
                        if fontexps then
                            local expansion = fontexps[cur_p.char]
                            if expansion then
                                active_width.adjust_stretch = active_width.adjust_stretch + expansion.glyphstretch
                                active_width.adjust_shrink  = active_width.adjust_shrink  + expansion.glyphshrink
                            end
                        end
                    end
                end
                cur_p = cur_p.next
            end
            if not cur_p then -- TODO
                report_parbuilders("problems with linebreak_tail")
                os.exit()
            end
            local id = cur_p.id
            if id == hlist_code or id == vlist_code then
                if is_parallel[cur_p.dir][par.line_break_dir] then
                    active_width.size = active_width.size + cur_p.width
                else
                    active_width.size = active_width.size + cur_p.depth + cur_p.height
                end
            elseif id == glue_code then
                if par.auto_breaking then
                    local prev_p = cur_p.prev
                    if prev_p and prev_p ~= temp_head then
                        local id = prev_p.id
                        if id == glyph_code or
                            (id < math_code and (id ~= whatsit_code or prev_p.subtype ~= dir_code)) or -- was: precedes_break(prev_p)
                            (id == kern_code and prev_p.subtype ~= userkern_code) then
                            try_break(0, unhyphenated_code, par, first_p, cur_p, checked_expansion)
                        end
                    end
                end
                local spec = check_shrinkage(par,cur_p.spec)
                local order = stretch_orders[spec.stretch_order]
                cur_p.spec = spec
                active_width.size   = active_width.size   + spec.width
                active_width[order] = active_width[order] + spec.stretch
                active_width.shrink = active_width.shrink + spec.shrink
            elseif id == disc_code then
                local subtype = cur_p.subtype
                if subtype ~= second_disc_code then -- are there still second_disc_code in luatex
                    local line_break_dir = par.line_break_dir
                    if par.second_pass then -- todo: make second pass local
                        local actual_pen = subtype == automatic_disc_code and par.ex_hyphen_penalty or par.hyphen_penalty
                        local pre = cur_p.pre
                        if not pre then    --  trivial pre-break
                            disc_width.size = 0
                            if checked_expansion then
                                disc_width.adjust_stretch = 0
                                disc_width.adjust_shrink  = 0
                            end
                            try_break(actual_pen, hyphenated_code, par, first_p, cur_p, checked_expansion)
                        else
                            local size, adjust_stretch, adjust_shrink = add_to_width(line_break_dir,checked_expansion,pre)
                            disc_width.size   = size
                            active_width.size = active_width.size + size
                            if checked_expansion then
                                disc_width.adjust_stretch   = adjust_stretch
                                disc_width.adjust_shrink    = adjust_shrink
                                active_width.adjust_stretch = active_width.adjust_stretch + adjust_stretch
                                active_width.adjust_shrink  = active_width.adjust_shrink  + adjust_shrink
                            else
                             -- disc_width.adjust_stretch = 0
                             -- disc_width.adjust_shrink  = 0
                            end
                            try_break(actual_pen, hyphenated_code, par, first_p, cur_p, checked_expansion)
                            if subtype == first_disc_code then
                                local cur_p_next = cur_p.next
                                if cur_p_next.id ~= disc_code or cur_p_next.subtype ~= second_disc_code then
                                    report_parbuilders("unsupported disc at location %a",1)
                                else
                                    local pre = cur_p_next.pre
                                    if pre then
                                        local size, adjust_stretch, adjust_shrink = add_to_width(line_break_dir,checked_expansion,pre)
                                        disc_width.size = disc_width.size + size
                                        if checked_expansion then
                                            disc_width.adjust_stretch = disc_width.adjust_stretch + adjust_stretch
                                            disc_width.adjust_shrink  = disc_width.adjust_shrink  + adjust_shrink
                                        end
                                        try_break(actual_pen, hyphenated_code, par, first_p, cur_p_next, checked_expansion)
                                        --
                                        -- I will look into this some day ... comment in linebreak.w says that this fails,
                                        -- maybe this is what Taco means with his comment in the luatex manual.
                                        --
                                        -- do_one_seven_eight(sub_disc_width_from_active_width);
                                        -- do_one_seven_eight(reset_disc_width);
                                        -- s = vlink_no_break(vlink(cur_p));
                                        -- add_to_widths(s, line_break_dir, pdf_adjust_spacing,disc_width);
                                        -- ext_try_break(...,first_p,vlink(cur_p));
                                        --
                                    else
                                        report_parbuilders("unsupported disc at location %a",2)
                                    end
                                end
                            end
                            -- beware, we cannot restore to a saved value as the try_break adapts active_width
                            active_width.size = active_width.size - disc_width.size
                            if checked_expansion then
                                active_width.adjust_stretch = active_width.adjust_stretch - disc_width.adjust_stretch
                                active_width.adjust_shrink  = active_width.adjust_shrink  - disc_width.adjust_shrink
                            end
                        end
                    end
                    local replace = cur_p.replace
                    if replace then
                        local size, adjust_stretch, adjust_shrink = add_to_width(line_break_dir,checked_expansion,replace)
                        active_width.size = active_width.size + size
                        if checked_expansion then
                            active_width.adjust_stretch = active_width.adjust_stretch + adjust_stretch
                            active_width.adjust_shrink  = active_width.adjust_shrink  + adjust_shrink
                        end
                    end
                end
            elseif id == kern_code then
                if cur_p.subtype == userkern_code then
                    kern_break(par,cur_p,first_p, checked_expansion)
                else
                    local d = cur_p.kern
                    of d ~= 0 then 
                        active_width.size = active_width.size + d
                        if checked_expansion and expand_kerns and (cur_p.subtype == kerning_code or cur_p[a_fontkern]) then
                            local stretch, shrink = kern_stretch_shrink(cur_p,d)
                            if expand_kerns == "stretch" then
                                active_width.adjust_stretch = active_width.adjust_stretch + stretch
                            elseif expand_kerns == "shrink" then
                                active_width.adjust_shrink  = active_width.adjust_shrink  + shrink
                            else
                                active_width.adjust_stretch = active_width.adjust_stretch + stretch
                                active_width.adjust_shrink  = active_width.adjust_shrink  + shrink
                            end
                        end
                    end
                end
            elseif id == math_code then
                par.auto_breaking = cur_p.subtype == endmath_code
                kern_break(par,cur_p, first_p, checked_expansion)
            elseif id == rule_code then
                active_width.size = active_width.size + cur_p.width
            elseif id == penalty_code then
                try_break(cur_p.penalty, unhyphenated_code, par, first_p, cur_p, checked_expansion)
            elseif id == whatsit_code then
                local subtype = cur_p.subtype
                if subtype == localpar_code then
                    par.internal_pen_inter       = cur_p.pen_inter
                    par.internal_pen_broken      = cur_p.pen_broken
                    par.internal_left_box        = cur_p.box_left
                    par.internal_left_box_width  = cur_p.box_left_width
                    par.internal_right_box       = cur_p.box_right
                    par.internal_right_box_width = cur_p.box_right_width
                elseif subtype == dir_code then
                    par.line_break_dir = checked_line_dir(dirstack) or par.line_break_dir
                else
                    local get_width = get_whatsit_width[subtype]
                    if get_width then
                        active_width.size = active_width.size + get_width(cur_p)
                    end
                end
            elseif id == mark_code or id == ins_code or id == adjust_code then
                -- skip
            else
                report_parbuilders("node of type %a found in paragraph",type(id))
            end
            cur_p = cur_p.next
        end
        if not cur_p then
            try_break(eject_penalty, hyphenated_code, par, first_p, cur_p, checked_expansion)
            local p_active = par.active
            local n_active = p_active.next
            if n_active ~= p_active then
                local r = n_active
                par.fewest_demerits = awful_badness
                repeat -- use local d
                    if r.id ~= delta_code and r.total_demerits < par.fewest_demerits then
                        par.fewest_demerits = r.total_demerits
                        par.best_bet = r
                    end
                    r = r.next
                until r == p_active
                par.best_line = par.best_bet.line_number
                local asked_looseness = par.looseness
                if asked_looseness == 0 then
                    return wrap_up(par)
                end
                local r = n_active
                local actual_looseness = 0
                -- minimize assignments to par but happens seldom
                repeat
                    if r.id ~= delta_code then
                        local line_diff = r.line_number - par.best_line
                        par.line_diff = line_diff
                        if (line_diff < actual_looseness and asked_looseness <= line_diff)   or
                           (line_diff > actual_looseness and asked_looseness >= line_diff) then
                            par.best_bet = r
                            actual_looseness = line_diff
                            par.fewest_demerits = r.total_demerits
                        elseif line_diff == actual_looseness and r.total_demerits < par.fewest_demerits then
                            par.best_bet = r
                            par.fewest_demerits = r.total_demerits
                        end
                    end
                    r = r.next
                until r == p_active -- weird, loop list?
                par.best_line = par.best_bet.line_number
                if actual_looseness == asked_looseness or par.final_pass then
                    return wrap_up(par)
                end
            end
        end
        reset_meta(par) -- clean up the memory by removing the break nodes
        if not par.second_pass then
            if tracing_paragraphs then
                diagnostics.current_pass(par,"secondpass")
            end
            par.threshold = par.tolerance
            par.second_pass = true
            par.final_pass = par.emergency_stretch <= 0
        else
            if tracing_paragraphs then
                diagnostics.current_pass(par,"emergencypass")
            end
            par.background.stretch = par.background.stretch + par.emergency_stretch
            par.final_pass = true
        end
    end
    return wrap_up(par)
end

-- standard tex logging .. will be adapted ..

local function write_esc(cs)
    local esc = tex.escapechar
    if esc then
        write("log",utfchar(esc),cs)
    else
        write("log",cs)
    end
end

function diagnostics.start()
end

function diagnostics.stop()
    write_nl("log",'')
end

function diagnostics.current_pass(par,what)
    write_nl("log",format("@%s",what))
end

local function short_display(a,font_in_short_display)
    while a do
        local id = a.id
        if id == glyph_code then
            local font = a.font
            if font ~= font_in_short_display then
                write("log",tex.fontidentifier(font) .. ' ')
                font_in_short_display = font
            end
            if a.subtype == ligature_code then
                font_in_short_display = short_display(a.components,font_in_short_display)
            else
                write("log",utfchar(a.char))
            end
--         elseif id == rule_code then
--             write("log","|")
--         elseif id == glue_code then
--             if a.spec.writable then
--                 write("log"," ")
--             end
--         elseif id == math_code then
--             write("log","$")
        elseif id == disc_code then
            font_in_short_display = short_display(a.pre,font_in_short_display)
            font_in_short_display = short_display(a.post,font_in_short_display)
        else -- no explicit checking
            write("log",format("[%s]",nodecodes[id]))
        end
        a = a.next
    end
    return font_in_short_display
end

diagnostics.short_display = short_display

function diagnostics.break_node(par, q, fit_class, break_type, cur_p) -- %d ?
    local passive = par.passive
    local typ_ind = break_type == hyphenated_code and '-' or ""
    if par.do_last_line_fit then
        local s = number.toscaled(q.active_short)
        local g = number.toscaled(q.active_glue)
        if cur_p then
            write_nl("log",format("@@%d: line %d.%d%s t=%s s=%s g=%s",
                passive.serial or 0,q.line_number-1,fit_class,typ_ind,q.total_demerits,s,g))
        else
            write_nl("log",format("@@%d: line %d.%d%s t=%s s=%s a=%s",
                passive.serial or 0,q.line_number-1,fit_class,typ_ind,q.total_demerits,s,g))
        end
    else
        write_nl("log",format("@@%d: line %d.%d%s t=%s",
            passive.serial or 0,q.line_number-1,fit_class,typ_ind,q.total_demerits))
    end
    if not passive.prev_break then
        write("log"," -> @0")
    else
        write("log",format(" -> @%d", passive.prev_break.serial or 0))
    end
end

function diagnostics.feasible_break(par, cur_p, r, b, pi, d, artificial_demerits)
    local printed_node = par.printed_node
    if printed_node ~= cur_p then
        write_nl("log","")
        if not cur_p then
            par.font_in_short_display = short_display(printed_node.next,par.font_in_short_display)
        else
            local save_link = cur_p.next
            cur_p.next = nil
            write_nl("log","")
            par.font_in_short_display = short_display(printed_node.next,par.font_in_short_display)
            cur_p.next = save_link
        end
        par.printed_node = cur_p
    end
    write_nl("log","@")
    if not cur_p then
        write_esc("par")
    else
        local id = cur_p.id
        if id == glue_code then
            -- print nothing
        elseif id == penalty_code then
            write_esc("penalty")
        elseif id == disc_code then
            write_esc("discretionary")
        elseif id == kern_code then
            write_esc("kern")
        elseif id == math_code then
            write_esc("math")
        else
            write_esc("unknown")
        end
    end
    local via, badness, demerits = 0, '*', '*'
    if r.break_node then
        via = r.break_node.serial or 0
    end
    if b <= infinite_badness then
        badness = tonumber(d) -- format("%d", b)
    end
    if not artificial_demerits then
        demerits = tonumber(d) -- format("%d", d)
    end
    write("log",format(" via @%d b=%s p=%s d=%s", via, badness, pi, demerits))
end

-- reporting --

statistics.register("alternative parbuilders", function()
    if nofpars > 0 then
        return format("%s paragraphs, %s lines (%s protruded, %s adjusted)", nofpars, noflines, nofprotrudedlines, nofadjustedlines)
    end
end)

-- actually scaling kerns is not such a good idea and it will become
-- configureable

-- This is no way a replacement for the built in (fast) packer
-- it's just an alternative for special (testing) purposes.
--
-- We could use two hpacks: one to be used in the par builder
-- and one to be used for other purposes. The one in the par
-- builder is much more simple as it does not need the expansion
-- code but only need to register the effective expansion factor
-- with the glyph.

local function glyph_width_height_depth(curdir,pdir,p)
    if is_rotated[curdir] then
        if is_parallel[curdir][pdir] then
            local half = (p.height + p.depth) / 2
            return p.width, half, half
        else
            local half = p.width / 2
            return p.height + p.depth, half, half
        end
    elseif is_rotated[pdir] then
        if is_parallel[curdir][pdir] then
            local half = (p.height + p.depth) / 2
            return p.width, half, half
        else
            return p.height + p.depth, p.width, 0 -- weird
        end
    else
        if glyphdir_is_equal[curdir][pdir] then
            return p.width, p.height, p.depth
        elseif is_opposite[curdir][pdir] then
            return p.width, p.depth, p.height
        else -- can this happen?
            return p.height + p.depth, p.width, 0 -- weird
        end
    end
end

local function pack_width_height_depth(curdir,pdir,p)
    if is_rotated[curdir] then
        if is_parallel[curdir][pdir] then
            local half = (p.height + p.depth) / 2
            return p.width, half, half
        else -- can this happen?
            local half = p.width / 2
            return p.height + p.depth, half, half
        end
    else
        if pardir_is_equal[curdir][pdir] then
            return p.width, p.height, p.depth
        elseif is_opposite[curdir][pdir] then
            return p.width, p.depth, p.height
        else -- weird dimensions, can this happen?
         -- return p.width, p.depth, p.height
            return p.height + p.depth, p.width, 0
        end
    end
end

-- local function xpack(head,width,method,direction,analysis)
--
--     -- inspect(analysis)
--
--     local expansion         = method == "cal_expand_ratio"
--     local natural           = analysis.size
--     local font_stretch      = analysis.adjust_stretch
--     local font_shrink       = analysis.adjust_shrink
--     local font_expand_ratio = 0
--     local delta             = width - natural
--
--     local hlist             = new_node("hlist")
--
--     hlist.list              = head
--     hlist.dir               = direction or tex.textdir
--     hlist.width             = width
--     hlist.height            = height
--     hlist.depth             = depth
--
--     if delta == 0 then
--
--         hlist.glue_sign  = 0
--         hlist.glue_order = 0
--         hlist.glue_set   = 0
--
--     else
--
--         local order = analysis.filll ~= 0 and fillcodes.filll or
--                       analysis.fill  ~= 0 and fillcodes.fill  or
--                       analysis.fil   ~= 0 and fillcodes.fil   or
--                       analysis.fi    ~= 0 and fillcodes.fi    or 0
--
--         if delta > 0 then
--
--             if expansion and order == 0 and font_stretch > 0 then
--                 font_expand_ratio = (delta/font_stretch) * 1000
--             else
--                 local stretch = analysis.stretch
--                 if stretch ~= 0 then
--                     hlist.glue_sign  = 1 -- stretch
--                     hlist.glue_order = order
--                     hlist.glue_set   = delta/stretch
--                 else
--                     hlist.glue_sign  = 0 -- nothing
--                     hlist.glue_order = order
--                     hlist.glue_set   = 0
--                 end
--             end
-- print("stretch",hlist.glue_sign,hlist.glue_order,hlist.glue_set)
--
--         else
--
--             if expansion and order == 0 and font_shrink > 0 then
--                 font_expand_ratio = (delta/font_shrink) * 1000
--             else
--                 local shrink = analysis.shrink
--                 if shrink ~= 0 then
--                     hlist.glue_sign  = 2 -- shrink
--                     hlist.glue_order = order
--                     hlist.glue_set   = - delta/shrink
--                 else
--                     hlist.glue_sign  = 0 -- nothing
--                     hlist.glue_order = order
--                     hlist.glue_set   = 0
--                 end
--             end
-- print("shrink",hlist.glue_sign,hlist.glue_order,hlist.glue_set)
--
--         end
--
--     end
--
--     if not expansion or font_expand_ratio == 0 then
--         -- nothing
--     elseif font_expand_ratio > 0 then
--         if font_expand_ratio > 1000 then
--             font_expand_ratio = 1000
--         end
--         local current = head
--         while current do
--             local id = current.id
--             if id == glyph_code then
--                 local stretch, shrink = char_stretch_shrink(current) -- get only one
--                 if stretch then
--                     if trace_expansion then
--                         setnodecolor(g,"hz:positive")
--                     end
--                     current.expansion_factor = font_expand_ratio * stretch
--                 end
--             elseif id == kern_code then
--                 local kern = current.kern
--                 if kern ~= 0 and current.subtype == kerning_code then
--                     current.kern = font_expand_ratio * current.kern
--                 end
--             end
--             current = current.next
--         end
--     elseif font_expand_ratio < 0 then
--         if font_expand_ratio < -1000 then
--             font_expand_ratio = -1000
--         end
--         local current = head
--         while current do
--             local id = current.id
--             if id == glyph_code then
--                 local stretch, shrink = char_stretch_shrink(current) -- get only one
--                 if shrink then
--                     if trace_expansion then
--                         setnodecolor(g,"hz:negative")
--                     end
--                     current.expansion_factor = font_expand_ratio * shrink
--                 end
--             elseif id == kern_code then
--                 local kern = current.kern
--                 if kern ~= 0 and current.subtype == kerning_code then
--                     current.kern = font_expand_ratio * current.kern
--                 end
--             end
--             current = current.next
--         end
--     end
--     return hlist, 0
-- end

local function hpack(head,width,method,direction) -- fast version when head = nil

    -- we can pass the adjust_width and adjust_height so that we don't need to recalculate them but
    -- with the glue mess it's less trivial as we lack detail

    local hlist = new_node("hlist")

    if head == nil then
        return hlist, 0
    end

    local cal_expand_ratio  = method == "cal_expand_ratio" or method == "subst_ex_font"

    direction               = direction or tex.textdir

    local line              = 0

    local height            = 0
    local depth             = 0
    local natural           = 0
    local font_stretch      = 0
    local font_shrink       = 0
    local font_expand_ratio = 0
    local last_badness      = 0
    local disc_stack        = { }
    local disc_level        = 0
    local expansion_stack   = cal_expand_ratio and { } -- todo: optionally pass this
    local expansion_index   = 0
    local total_stretch     = { [0] = 0, 0, 0, 0, 0 }
    local total_shrink      = { [0] = 0, 0, 0, 0, 0 }

    local hpack_dir         = direction

    local adjust_head       = texlists.adjust_head
    local pre_adjust_head   = texlists.pre_adjust_head
    local adjust_tail       = adjust_head and slide_nodes(adjust_head)
    local pre_adjust_tail   = pre_adjust_head and slide_nodes(pre_adjust_head)

    hlist.list = head
    hlist.dir  = hpack_dir

    new_dir_stack(hpack_dir)

    local checked_expansion = false

    if cal_expand_ratio then
        checked_expansion = { }
        setmetatableindex(checked_expansion,check_expand_lines)
    end

    -- this one also needs to check the font, so in the end indeed we might end up with two variants

    local fontexps, lastfont

    local current = head

    while current do
        local id = current.id
        if id == glyph_code then
            if cal_expand_ratio then
                local currentfont = current.font
                if currentfont ~= lastfont then
                    fontexps = checked_expansion[currentfont] -- a bit redundant for the par line packer
                    lastfont = currentfont
                end
                if fontexps then
                    local expansion = fontexps[current.char]
                    if expansion then
                        font_stretch = font_stretch + expansion.glyphstretch
                        font_shrink  = font_shrink  + expansion.glyphshrink
                        expansion_index = expansion_index + 1
                        expansion_stack[expansion_index] = current
                    end
                end
            end
            -- use inline if no expansion
            local wd, ht, dp = glyph_width_height_depth(hpack_dir,"TLT",current) -- was TRT ?
            natural = natural + wd
            if ht > height then
                height = ht
            end
            if dp > depth then
                depth = dp
            end
            current = current.next
        elseif id == kern_code then
            local kern = current.kern
            if kern == 0 then
                -- no kern
            else
                if cal_expand_ratio and expand_kerns and current.subtype == kerning_code or current[a_fontkern] then -- check p.kern
                    local stretch, shrink = kern_stretch_shrink(current,kern)
                    if expand_kerns == "stretch" then
                        font_stretch = font_stretch + stretch
                    elseif expand_kerns == "shrink" then
                        font_shrink  = font_shrink + shrink
                    else
                        font_stretch = font_stretch + stretch
                        font_shrink  = font_shrink + shrink
                    end
                    expansion_index = expansion_index + 1
                    expansion_stack[expansion_index] = current
                end
                natural = natural + kern
            end
            current = current.next
        elseif id == disc_code then
            if current.subtype ~= second_disc_code then
                -- we follow the end of line disc chain
                local replace = current.replace
                if replace then
                    disc_level = disc_level + 1
                    disc_stack[disc_level] = current.next
                    current = replace
                else
                    current = current.next
                end
            else
                current = current.next
            end
        elseif id == glue_code then
            local spec = current.spec
            natural = natural + spec.width
            local op = spec.stretch_order
            local om = spec.shrink_order
            total_stretch[op] = total_stretch[op] + spec.stretch
            total_shrink [om] = total_shrink [om] + spec.shrink
            if current.subtype >= leaders_code then
                local leader = current.leader
                local ht = leader.height
                local dp = leader.depth
                if ht > height then
                    height = ht
                end
                if dp > depth then
                    depth = dp
                end
            end
            current = current.next
        elseif id == hlist_code or id == vlist_code then
            local sh = current.shift
            local wd, ht, dp = pack_width_height_depth(hpack_dir,current.dir or hpack_dir,current) -- added: or pack_dir
            local hs, ds = ht - sh, dp + sh
            natural = natural + wd
            if hs > height then
                height = hs
            end
            if ds > depth then
                depth = ds
            end
            current = current.next
        elseif id == rule_code then
            local wd = current.width
            local ht = current.height
            local dp = current.depth
            natural = natural + wd
            if ht > height then
                height = ht
            end
            if dp > depth then
                depth = dp
            end
            current = current.next
        elseif id == math_code then
            natural = natural + current.surround
            current = current.next
        elseif id == unset_code then
            local wd = current.width
            local ht = current.height
            local dp = current.depth
            local sh = current.shift
            local hs = ht - sh
            local ds = dp + sh
            natural = natural + wd
            if hs > height then
                height = hs
            end
            if ds > depth then
                depth = ds
            end
            current = current.next
        elseif id == ins_code or id == mark_code then
            local prev = current.prev
            local next = current.next
            if adjust_tail then -- todo
                if next then
                    next.prev = prev
                end
                if prev then
                    prev.next = next
                end
                current.prev = adjust_tail
                current.next = nil
                adjust_tail.next = current
                adjust_tail = current
            else
                adjust_head = current
                adjust_tail = current
                current.prev = nil
                current.next = nil
            end
            current = next
        elseif id == adjust_code then
            local list = current.list
            if adjust_tail then
                adjust_tail.next = list
                adjust_tail = slide_nodes(list)
            else
                adjust_head = list
                adjust_tail = slide_nodes(list)
            end
            current = current.next
        elseif id == whatsit_code then
            local subtype = current.subtype
            if subtype == dir_code then
                hpack_dir = checked_line_dir(stack,current) or hpack_dir
            else
                local get_dimensions = get_whatsit_dimensions[subtype]
                if get_dimensions then
                    local wd, ht, dp = get_dimensions(current)
                    natural = natural + wd
                    if ht > height then
                        height = ht
                    end
                    if dp > depth then
                        depth = dp
                    end
                end
            end
            current = current.next
        elseif id == marginkern_code then
            if cal_expand_ratio then
                local glyph = current.glyph
                local char_pw = current.subtype == leftmargin_code and left_pw or right_pw
                font_stretch = font_stretch - current.width - char_pw(glyph)
                font_shrink  = font_shrink  - current.width - char_pw(glyph)
                expansion_index = expansion_index + 1
                expansion_stack[expansion_index] = glyph
            end
            natural = natural + current.width
            current = current.next
        else
            current = current.next
        end
        if not current and disc_level > 0 then
            current = disc_stack[disc_level]
            disc_level = disc_level - 1
        end
    end
    if adjust_tail then
        adjust_tail.next = nil -- todo
    end
    if pre_adjust_tail then
        pre_adjust_tail.next = nil -- todo
    end
    if mode == "additional" then
        width = width + natural
    end

    hlist.width  = width
    hlist.height = height
    hlist.depth  = depth

    local delta  = width - natural
    if delta == 0 then
        hlist.glue_sign = 0
        hlist.glue_order = 0
        hlist.glue_set = 0
    elseif delta > 0 then
        -- natural width smaller than requested width
        local order = (total_stretch[4] ~= 0 and 4 or total_stretch[3] ~= 0 and 3) or
                      (total_stretch[2] ~= 0 and 2 or total_stretch[1] ~= 0 and 1) or 0
--         local correction = 0
        if cal_expand_ratio and order == 0 and font_stretch > 0 then -- check sign of font_stretch
            font_expand_ratio = delta/font_stretch

            if font_expand_ratio > 1 then
                font_expand_ratio = 1
            end

            local fontexps, lastfont
            for i=1,expansion_index do
                local g = expansion_stack[i]
                local e
                if g.id == glyph_code then
                    local currentfont = g.font
                    if currentfont ~= lastfont then
                        fontexps = expansions[currentfont]
                        lastfont = currentfont
                    end
                    local data = fontexps[g.char]
                    if trace_expansion then
                        setnodecolor(g,"hz:positive")
                    end
                    e = font_expand_ratio * data.glyphstretch / 1000
--                     correction = correction + (e / 1000) * g.width
                else
                    local kern = g.kern
                    local stretch, shrink = kern_stretch_shrink(g,kern)
                    e = font_expand_ratio * stretch / 1000
--                     correction = correction + (e / 1000) * kern
                end
                g.expansion_factor = e
            end
        end
--         delta = delta - correction
        local tso = total_stretch[order]
        if tso ~= 0 then
            hlist.glue_sign  = 1
            hlist.glue_order = order
            hlist.glue_set   = delta/tso
        else
            hlist.glue_sign  = 0
            hlist.glue_order = order
            hlist.glue_set   = 0
        end
        if font_expand_ratio ~= 0 then
            -- todo
        elseif order == 0 then -- and hlist.list then
            last_badness = calculate_badness(delta,total_stretch[0])
            if last_badness > tex.hbadness then
                if last_badness > 100 then
                    diagnostics.underfull_hbox(hlist,line,last_badness)
                else
                    diagnostics.loose_hbox(hlist,line,last_badness)
                end
            end
        end
    else
        -- natural width larger than requested width
        local order = total_shrink[4] ~= 0 and 4 or total_shrink[3] ~= 0 and 3
                   or total_shrink[2] ~= 0 and 2 or total_shrink[1] ~= 0 and 1 or 0
--         local correction = 0
        if cal_expand_ratio and order == 0 and font_shrink > 0 then -- check sign of font_shrink
            font_expand_ratio = delta/font_shrink

            if font_expand_ratio < 1 then
                font_expand_ratio = -1
            end

            local fontexps, lastfont
            for i=1,expansion_index do
                local g = expansion_stack[i]
                local e
                if g.id == glyph_code then
                    local currentfont = g.font
                    if currentfont ~= lastfont then
                        fontexps = expansions[currentfont]
                        lastfont = currentfont
                    end
                    local data = fontexps[g.char]
                    if trace_expansion then
                        setnodecolor(g,"hz:negative")
                    end
                    e = font_expand_ratio * data.glyphshrink / 1000
                 -- local d = (e / 1000) * 1000
                 -- local eps = g.width - (1 + d / 1000000) * g.width
                 -- correction = correction + eps
                 -- e = d
--                     correction = correction + (e / 1000) * g.width
                else
                    local kern = g.kern
                    local stretch, shrink = kern_stretch_shrink(g,kern)
                    e = font_expand_ratio * shrink / 1000
--                     correction = correction + (e / 1000) * kern
                end
                g.expansion_factor = e
            end
        end
--         delta = delta - correction
        local tso = total_shrink[order]
        if tso ~= 0 then
            hlist.glue_sign  = 2
            hlist.glue_order = order
            hlist.glue_set   = -delta/tso
        else
            hlist.glue_sign  = 0
            hlist.glue_order = order
            hlist.glue_set   = 0
        end
        if font_expand_ratio ~= 0 then
            -- todo
        elseif tso < -delta and order == 0 then -- and hlist.list then
            last_badness = 1000000
            hlist.glue_set = 1
            local fuzz = - delta - total_shrink[0]
            local hfuzz = tex.hfuzz
            if fuzz > hfuzz or tex.hbadness < 100 then
                local overfullrule = tex.overfullrule
                if fuzz > hfuzz and overfullrule > 0 then
                    -- weird, is always called and no rules shows up
                    slide_nodes(list).next = new_rule(overfullrule,nil,nil,hlist.dir)
                end
                diagnostics.overfull_hbox(hlist,line,-delta)
            end
        elseif order == 0 and hlist.list and last_badness > tex.hbadness then
            diagnostics.bad_hbox(hlist,line,last_badness)
        end
    end
    return hlist, last_badness
end

xpack_nodes = hpack -- comment this for old fashioned expansion

local function common_message(hlist,line,str)
    write_nl("")
    if status.output_active then -- unset
        write(str," has occurred while \\output is active")
    end
    local fileline = status.linenumber
    if line > 0 then
        write(str," in paragraph at lines ",fileline,"--",fileline+line-1)
    elseif line < 0 then
        write(str," in alignment at lines ",fileline,"--",fileline-line-1)
    else
        write(str," detected at line ",fileline)
    end
    write_nl("")
    diagnostics.short_display(hlist.list,false)
    write_nl("")
 -- diagnostics.start()
 -- show_box(hlist.list)
 -- diagnostics.stop()
end

function diagnostics.overfull_hbox(hlist,line,d)
    common_message(hlist,line,format("Overfull \\hbox (%spt too wide)",number.toscaled(d)))
end

function diagnostics.bad_hbox(hlist,line,b)
    common_message(hlist,line,format("Tight \\hbox (badness %i)",b))
end

function diagnostics.underfull_hbox(hlist,line,b)
    common_message(hlist,line,format("Underfull \\hbox (badness %i)",b))
end

function diagnostics.loose_hbox(hlist,line,b)
    common_message(hlist,line,format("Loose \\hbox (badness %i)",b))
end

-- e = font_expand_ratio * data.glyphstretch / 1000
-- local stretch = data.stretch
-- if e >= stretch then
--     e = stretch
-- else
--     local step = 5
--     e = math.round(e/step) * step
-- end

-- local shrink = - data.shrink
-- if e <= shrink then
--     e = shrink
-- else
--     local step = 5
--     e = math.round(e/step) * step
-- end
