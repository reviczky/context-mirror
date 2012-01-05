if not modules then modules = { } end modules ['tabl-xtb'] = {
    version   = 1.001,
    comment   = "companion to tabl-xtb.mkvi",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

--[[

This table mechanism is a combination between TeX and Lua. We do process
cells at the TeX end and inspect them at the Lua end. After some analysis
we have a second pass using the calculated widths, and if needed cells
will go through a third pass to get the heights right. This last pass is
avoided when possible which is why some code below looks a bit more
complex than needed. The reason for such optimizations is that each cells
is actually a framed instance and because tables like this can be hundreds
of pages we want to keep processing time reasonable.

To a large extend the behaviour is comparable with the way bTABLE/eTABLE
works and there is a module that maps that one onto this one. Eventually
this mechamism will be improved so that it can replace its older cousin.

]]--

-- todo: use linked list instead of r/c array

local texdimen    = tex.dimen
local texcount    = tex.count
local texbox      = tex.box
local texsetcount = tex.setcount
local texsetdimen = tex.setdimen

local format      = string.format
local concat      = table.concat

local context                 = context
local context_beginvbox       = context.beginvbox
local context_endvbox         = context.endvbox
local context_blank           = context.blank
local context_nointerlineskip = context.nointerlineskip

local variables               = interfaces.variables

local setmetatableindex       = table.setmetatableindex
local copy_node_list          = node.copy_list
local hpack_node_list         = node.hpack
local vpack_node_list         = node.vpack
local slide_node_list         = node.slide
local flush_node_list         = node.flush_list

local new_glue                = nodes.pool.glue
local new_kern                = nodes.pool.kern

local v_stretch               = variables.stretch
local v_normal                = variables.normal
local v_width                 = variables.width
local v_repeat                = variables["repeat"]

xtables = { } -- maybe in typesetters

local trace_xtable  = false  trackers.register("xtable.construct", function(v) trace_xtable = v end)

local report_xtable = logs.reporter("xtable")

local head_mode = 1
local foot_mode = 2
local more_mode = 3
local body_mode = 4

local stack, data = { }, nil

function xtables.create(settings)
    table.insert(stack,data)
    local rows         = { }
    local widths       = { }
    local heights      = { }
    local depths       = { }
    local spans        = { }
    local distances    = { }
    local autowidths   = { }
    local modes        = { }
    local fixedrows    = { }
    local fixedcolumns = { }
    data = {
        rows          = rows,
        widths        = widths,
        heights       = heights,
        depths        = depths,
        spans         = spans,
        distances     = distances,
        modes         = modes,
        autowidths    = autowidths,
        fixedrows     = fixedrows,
        fixedcolumns  = fixedcolumns,
        nofrows       = 0,
        nofcolumns    = 0,
        currentrow    = 0,
        currentcolumn = 0,
        settings      = settings or { },
    }
    local function add_zero(t,k)
        t[k] = 0
        return 0
    end
    local function add_cell(row,c)
        local cell = {
            nx     = 0,
            ny     = 0,
            list   = false,
        }
        row[c] = cell
        if c > data.nofcolumns then
            data.nofcolumns = c
        end
        return cell
    end
    local function add_row(rows,r)
        local row = { }
        setmetatableindex(row,add_cell)
        rows[r] = row
        if r > data.nofrows then
            data.nofrows = r
        end
        return row
    end
    setmetatableindex(rows,add_row)
    setmetatableindex(widths,add_zero)
    setmetatableindex(heights,add_zero)
    setmetatableindex(depths,add_zero)
    setmetatableindex(distances,add_zero)
    setmetatableindex(modes,add_zero)
    --
    settings.columndistance = tonumber(settings.columndistance) or 0
    settings.rowdistance = tonumber(settings.rowdistance) or 0
    settings.leftmargindistance = tonumber(settings.leftmargindistance) or 0
    settings.rightmargindistance = tonumber(settings.rightmargindistance) or 0
    settings.options = utilities.parsers.settings_to_hash(settings.option)
    settings.textwidth = tonumber(settings.textwidth) or tex.hsize
    settings.maxwidth = tonumber(settings.maxwidth) or settings.textwidth/8
 -- if #stack > 0 then
 --     settings.textwidth = tex.hsize
 -- end
end

function xtables.initialize_reflow_width()
    local r = data.currentrow
    local c = data.currentcolumn + 1
    local drc = data.rows[r][c]
    drc.nx = texcount.x_table_nx
    drc.ny = texcount.x_table_ny
    local distances = data.distances
    local distance = texdimen.x_table_distance
    if distance > distances[c] then
        distances[c] = distance
    end
    data.currentcolumn = c
end

function xtables.set_reflow_width()
    local r = data.currentrow
    local c = data.currentcolumn
    local rows = data.rows
    local row = rows[r]
    while row[c].span do -- can also be previous row ones
        c = c + 1
    end
    local tb = texbox.x_table_box
    local drc = row[c]
    --
    drc.list = true -- we don't need to keep the content around as we're in trial mode (no: copy_node_list(tb))
    --
    local widths, width = data.widths, tb.width
    if width > widths[c] then
        widths[c] = width
    end
    local heights, height = data.heights, tb.height
    if height > heights[r] then
        heights[r] = height
    end
    local depths, depth = data.depths, tb.depth
    if depth > depths[r] then
        depths[r] = depth
    end
    --
    local dimensionstate = texcount.frameddimensionstate
    if dimensionstate == 1 then
        data.fixedcolumns[c] = width
    elseif dimensionstate == 2 then
        data.fixedrows[r]    = height
    elseif dimensionstate == 3 then
        data.fixedrows[r]    = width
        data.fixedcolumns[c] = height
    end
    drc.dimensionstate = dimensionstate
    --
    local nx, ny = drc.nx, drc.ny
    if nx > 1 or ny > 1 then
        local spans = data.spans
        local self = true
        for y=1,ny do
            for x=1,nx do
                if self then
                    self = false
                else
                    local ry = r + y - 1
                    local cx = c + x - 1
                    if y > 1 then
                        spans[ry] = true
                    end
                    rows[ry][cx].span = true
                end
            end
        end
        c = c + nx - 1
    end
    if c > data.nofcolumns then
        data.nofcolumns = c
    end
    data.currentcolumn = c
end

function xtables.initialize_reflow_height()
    local r = data.currentrow
    local c = data.currentcolumn + 1
    local rows = data.rows
    local row = rows[r]
    while row[c].span do -- can also be previous row ones
        c = c + 1
    end
    data.currentcolumn = c
    local widths = data.widths
    local w = widths[c]
    local drc = row[c]
    for x=1,drc.nx-1 do
        w = w + widths[c+x]
    end
    texdimen.x_table_width = w
    local dimensionstate = drc.dimensionstate or 0
    if dimensionstate == 1 or dimensionstate == 3 then
        -- width was fixed so height is known
        texcount.x_table_skip_mode = 1
    elseif dimensionstate == 2 then
        -- height is enforced
        texcount.x_table_skip_mode = 1
    elseif data.autowidths[c] then
        -- width has changed so we need to recalculate the height
        texcount.x_table_skip_mode = 0
    else
        texcount.x_table_skip_mode = 1
    end
end

function xtables.set_reflow_height()
    local r = data.currentrow
    local c = data.currentcolumn
    local rows = data.rows
    local row = rows[r]
--     while row[c].span do -- we could adapt drc.nx instead
--         c = c + 1
--     end
    local tb = texbox.x_table_box
    local drc = row[c]
    if not data.fixedrows[r] then --  and drc.dimensionstate < 2
        local heights, height = data.heights, tb.height
        if height > heights[r] then
            heights[r] = height
        end
        local depths, depth = data.depths, tb.depth
        if depth > depths[r] then
            depths[r] = depth
        end
    end
--     c = c + drc.nx - 1
--     data.currentcolumn = c
end

function xtables.initialize_construct()
    local r = data.currentrow
    local c = data.currentcolumn + 1
    local rows = data.rows
    local row = rows[r]
    while row[c].span do -- can also be previous row ones
        c = c + 1
    end
    data.currentcolumn = c
    local widths = data.widths
    local heights = data.heights
    local depths = data.depths
    local w = widths[c]
    local h = heights[r]
    local d = depths[r]
    local drc = row[c]
    for x=1,drc.nx-1 do
        w = w + widths[c+x]
    end
    for y=1,drc.ny-1 do
        h = h + heights[r+y]
        d = d + depths[r+y]
    end
    texdimen.x_table_width = w
    texdimen.x_table_height = h + d
    texdimen.x_table_depth = 0
end

function xtables.set_construct()
    local r = data.currentrow
    local c = data.currentcolumn
    local rows = data.rows
    local row = rows[r]
--     while row[c].span do -- can also be previous row ones
--         c = c + 1
--     end
    local drc = row[c]
    -- this will change as soon as in luatex we can reset a box list without freeing
    drc.list = copy_node_list(texbox.x_table_box)
--     c = c + drc.nx - 1
--     data.currentcolumn = c
end

function xtables.reflow_width()
    local nofrows = data.nofrows
    local nofcolumns = data.nofcolumns
    local rows = data.rows
    for r=1,nofrows do
        local row = rows[r]
        for c=1,nofcolumns do
            local drc = row[c]
            if drc.list then
             --- flush_node_list(drc.list)
                drc.list = false
            end
        end
    end
    -- spread
    local settings = data.settings
    local options = settings.options
    local maxwidth = settings.maxwidth
    -- calculate width
    local widths = data.widths
    local distances = data.distances
    local autowidths = data.autowidths
    local fixedcolumns = data.fixedcolumns
    local width = 0
    local distance = 0
    local nofwide = 0
    local widetotal = 0
    if options[variables.max] then
        for c=1,nofcolumns do
            width = width + widths[c]
            if width > maxwidth then
                autowidths[c] = true
                nofwide = nofwide + 1
                widetotal = widetotal + widths[c]
            end
            if c < nofcolumns then
                distance = distance + distances[c]
            end
        end
    else
        for c=1,nofcolumns do -- also keep track of forced
            local fixedwidth = fixedcolumns[c]
            if fixedwidth then
                widths[c] = fixedwidth
                width = width + fixedwidth
            else
                width = width + widths[c]
                if width > maxwidth then
                    autowidths[c] = true
                    nofwide = nofwide + 1
                    widetotal = widetotal + widths[c]
                end
            end
            if c < nofcolumns then
                distance = distance + distances[c]
            end
        end
    end
    local delta = settings.textwidth - width - distance - (nofcolumns-1) * settings.columndistance
        - settings.leftmargindistance - settings.rightmargindistance
    --
    if delta == 0 then
        -- nothing to be done
    elseif delta > 0 then
        -- we can distribute some
        if not options[v_stretch] then
            -- not needed
        elseif options[v_width] then
            for c=1,nofcolumns do
                widths[c] = widths[c] + delta * widths[c] / width
            end
        else
            local plus = delta / nofcolumns
            for c=1,nofcolumns do
                widths[c] = widths[c] + plus
            end
        end
    elseif nofwide > 0 then
        if options[v_width] then
            -- proportionally
            for c=1,nofcolumns do
                local minus = - delta / nofwide
                if autowidths[c] then
                    widths[c] = widths[c] - minus
                end
            end
        else
            -- we can also consider a loop adding small amounts till
            -- we have a fit etc which is sometimes nicer
            local available = (widetotal + delta) / nofwide
            for c=1,nofcolumns do
                if autowidths[c] and available >= widths[c] then
                    autowidths[c] = nil
                    nofwide = nofwide - 1
                    widetotal = widetotal - widths[c]
                end
            end
            local available = (widetotal + delta) / nofwide
            for c=1,nofcolumns do
                if autowidths[c] then
                    widths[c] = available
                end
            end
            -- maybe stretch
        end
    end
    --
    data.currentrow = 0
    data.currentcolumn = 0
end

function xtables.reflow_height()
    data.currentrow = 0
    data.currentcolumn = 0
end

function xtables.construct()
    local rows = data.rows
    local heights = data.heights
    local depths = data.depths
    local widths = data.widths
    local spans = data.spans
    local distances = data.distances
    local modes = data.modes
    local settings = data.settings
    local nofcolumns = data.nofcolumns
    local nofrows = data.nofrows
    local columndistance = settings.columndistance
    local rowdistance = settings.rowdistance
    local leftmargindistance = settings.leftmargindistance
    local rightmargindistance = settings.rightmargindistance
    -- ranges can be mixes so we collect

    if trace_xtable then
        for r=1,data.nofrows do
            local line = { }
            for c=1,data.nofcolumns do
                local cell =rows[r][c]
                if cell.list then
                    line[#line+1] = "list"
                elseif cell.span then
                    line[#line+1] = "span"
                else
                    line[#line+1] = "none"
                end
            end
            report_xtable("%3d : %s",r,concat(line," "))
        end
    end

    local ranges = {
        [head_mode] = { },
        [foot_mode] = { },
        [more_mode] = { },
        [body_mode] = { },
    }
    for r=1,nofrows do
        local m = modes[r]
        if m == 0 then
            m = body_mode
        end
        local range = ranges[m]
        range[#range+1] = r
    end
    -- todo: hook in the splitter ... the splitter can ask for a chunk of
    -- a certain size ... no longer a split memory issue then and header
    -- footer then has to happen here too .. target height
    local function packaged_column(r)
        local row = rows[r]
        local start = nil
        local stop = nil
        if leftmargindistance > 0 then
            start = new_kern(leftmargindistance)
            stop = start
        end
        for c=1,nofcolumns do
            local drc = row[c]
            local list = drc.list
            if list then
                list.shift = list.height + list.depth
                list = hpack_node_list(list) -- is somehow needed
                list.width = 0
                list.height = 0
                list.depth = 0
                if start then
                    stop.next = list
                    list.prev = stop
                else
                    start = list
                end
                stop = list -- one node anyway, so not needed: slide_node_list(list)
            end
            local step = widths[c]
            if c < nofcolumns then
                step = step + columndistance + distances[c]
            end
            local kern = new_kern(step)
            if stop then
                stop.prev = kern
                stop.next = kern
            else -- can be first spanning next row (ny=...)
                start = kern
            end
            stop = kern
        end
        if start then
            if rightmargindistance > 0 then
                local kern = new_kern(rightmargindistance)
                stop.next = kern
                kern.prev = stop
             -- stop = kern
            end
            return start, heights[r] + depths[r]
        end
    end
    local function collect_range(range)
        local result = { }
        local nofrange = #range
        for i=1,#range do
            local r = range[i]
            local row = rows[r]
            local list, size = packaged_column(r)
            if list then
                result[#result+1] = {
                    hpack_node_list(list),
                    size,
                    i < nofrange and rowdistance > 0 and rowdistance or false, -- might move
                }
            end
        end
        return result
    end
    local body = collect_range(ranges[body_mode])
    data.results = {
        [head_mode] = collect_range(ranges[head_mode]),
        [foot_mode] = collect_range(ranges[foot_mode]),
        [more_mode] = collect_range(ranges[more_mode]),
        [body_mode] = body,
    }
    if #body == 0 then
        texsetcount("global","x_table_state",0)
        texsetdimen("global","x_table_final_width",0)
    else
        texsetcount("global","x_table_state",1)
        texsetdimen("global","x_table_final_width",body[1][1].width)
    end
end

local function inject(row,copy,package)
    local list = row[1]
    if copy then
        row[1] = copy_node_list(list)
    end
    if package then
        context_beginvbox()
        context(list)
        context(new_kern(row[2]))
        context_endvbox()
        context_nointerlineskip() -- figure out a better way
        if row[3] then
            context_blank(row[3] .. "sp")
        else
            context(new_glue(0))
        end
    else
        context(list)
        context(new_kern(row[2]))
        if row[3] then
            context(new_glue(row[3]))
        end
    end
end

local function total(row,distance)
    local n = #row > 0 and rowdistance or 0
    for i=1,#row do
        local ri = row[i]
        n = n + ri[2] + (ri[3] or 0)
    end
    return n
end

-- local function append(list,what)
--     for i=1,#what do
--         local l = what[i]
--         list[#list+1] = l[1]
--         local k = l[2] + (l[3] or 0)
--         if k ~= 0 then
--             list[#list+1] = new_kern(k)
--         end
--     end
-- end

function xtables.flush(directives) -- todo split by size / no inbetween then ..  glue list kern blank
    local vsize = directives.vsize
    local method = directives.method or v_normal
    local settings = data.settings
    local results  = data.results
    local rowdistance = settings.rowdistance
    local head = results[head_mode]
    local foot = results[foot_mode]
    local more = results[more_mode]
    local body = results[body_mode]
    local repeatheader = settings.header == v_repeat
    local repeatfooter = settings.footer == v_repeat
    if vsize and vsize > 0 then
        context_beginvbox()
        local bodystart = data.bodystart or 1
        local bodystop  = data.bodystop or #body
        if bodystart > 0 and bodystart <= bodystop then
            local bodysize = vsize
            local footsize = total(foot,rowdistance)
            local headsize = total(head,rowdistance)
            local moresize = total(more,rowdistance)
            local firstsize = body[bodystart][2]
            if bodystart == 1 then -- first chunk gets head
                bodysize = bodysize - headsize - footsize
                if headsize > 0 and bodysize >= firstsize then
                    for i=1,#head do
                        inject(head[i],repeatheader)
                    end
                    if rowdistance > 0 then
                        context(new_glue(rowdistance))
                    end
                    if not repeatheader then
                        results[head_mode] = { }
                    end
                end
            elseif moresize > 0 then -- following chunk gets next
                bodysize = bodysize - footsize - moresize
                if bodysize >= firstsize then
                    for i=1,#more do
                        inject(more[i],true)
                    end
                    if rowdistance > 0 then
                        context(new_glue(rowdistance))
                    end
                end
            elseif headsize > 0 and repeatheader then -- following chunk gets head
                bodysize = bodysize - footsize - headsize
                if bodysize >= firstsize then
                    for i=1,#head do
                        inject(head[i],true)
                    end
                    if rowdistance > 0 then
                        context(new_glue(rowdistance))
                    end
                end
            else -- following chunk gets nothing
                bodysize = bodysize - footsize
            end
            if bodysize >= firstsize then
                for i=bodystart,bodystop do -- room for improvement
                    local bi = body[i]
                    local bs = bodysize - bi[2] - (bi[3] or 0)
                    if bs > 0 then
                        inject(bi)
                        bodysize = bs
                        bodystart = i + 1
                        body[i] = nil
                    else
                        break
                    end
                end
                if bodystart > bodystop then
                    -- all is flushed and footer fits
                    if footsize > 0 then
                        if rowdistance > 0 then
                            context(new_glue(rowdistance))
                        end
                        for i=1,#foot do
                            inject(foot[i])
                        end
                        results[foot_mode] = { }
                    end
                    results[body_mode] = { }
                    texsetcount("global","x_table_state",0)
                else
                    -- some is left so footer is delayed
                    -- todo: try to flush a few more lines
                    if repeatfooter and footsize > 0 then
                        if rowdistance > 0 then
                            context(new_glue(rowdistance))
                        end
                        for i=1,#foot do
                            inject(foot[i],true)
                        end
                    else
                        -- todo: try to fit more of body
                    end
                    texsetcount("global","x_table_state",2)
                end
            else
                if firstsize > vsize then
                    -- get rid of the too large cell
                    inject(body[bodystart])
                    body[bodystart] = nil
                    bodystart = bodystart + 1
                end
                texsetcount("global","x_table_state",2) -- 1
            end
        else
            texsetcount("global","x_table_state",0)
        end
        data.bodystart = bodystart
        data.bodystop = bodystop
        context_endvbox()
    else
        if method == variables.split then
            -- maybe also a non float mode with header/footer repeat although
            -- we can also use a float without caption
            for i=1,#head do
                inject(head[i],false,true)
            end
            if #head > 0 and rowdistance > 0 then
                context_blank(rowdistance .. "sp")
            end
            for i=1,#body do
                inject(body[i],false,true)
            end
            if #foot > 0 and rowdistance > 0 then
                context_blank(rowdistance .. "sp")
            end
            for i=1,#foot do
                inject(foot[i],false,true)
            end
        else -- normal
            context_beginvbox()
            for i=1,#head do
                inject(head[i])
            end
            if #head > 0 and rowdistance > 0 then
                context(new_glue(rowdistance))
            end
            for i=1,#body do
                inject(body[i])
            end
            if #foot > 0 and rowdistance > 0 then
                context(new_glue(rowdistance))
            end
            for i=1,#foot do
                inject(foot[i])
            end
            context_endvbox()
        end
        results[head_mode] = { }
        results[body_mode] = { }
        results[foot_mode] = { }
        texsetcount("global","x_table_state",0)
    end
end

function xtables.cleanup()
    for mode, result in next, data.results do
        for _, r in next, result do
            flush_node_list(r[1])
        end
    end
    data = table.remove(stack)
end

function xtables.next_row()
    local r = data.currentrow + 1
    data.modes[r] = texcount.x_table_mode
    data.currentrow = r
    data.currentcolumn = 0
end

-- eventually we might only have commands

commands.x_table_create             = xtables.create
commands.x_table_reflow_width       = xtables.reflow_width
commands.x_table_reflow_height      = xtables.reflow_height
commands.x_table_construct          = xtables.construct
commands.x_table_flush              = xtables.flush
commands.x_table_cleanup            = xtables.cleanup
commands.x_table_next_row           = xtables.next_row
commands.x_table_init_reflow_width  = xtables.initialize_reflow_width
commands.x_table_init_reflow_height = xtables.initialize_reflow_height
commands.x_table_init_construct     = xtables.initialize_construct
commands.x_table_set_reflow_width   = xtables.set_reflow_width
commands.x_table_set_reflow_height  = xtables.set_reflow_height
commands.x_table_set_construct      = xtables.set_construct
