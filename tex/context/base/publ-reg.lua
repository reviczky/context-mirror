if not modules then modules = { } end modules ['publ-reg'] = {
    version   = 1.001,
    comment   = "this module part of publication support",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

local formatters = string.formatters
local sortedhash = table.sortedhash
local lpegmatch  = lpeg.match

local context        = context
local commands       = commands

local variables      = interfaces.variables

local v_once         = variables.once
local v_standard     = variables.standard
local v_stop         = variables.stop
local v_all          = variables.all

local datasets       = publications.datasets
local specifications = { }
local sequence       = { }
local flushers       = { }

function commands.setbtxregister(specification)
    local name     = specification.name
    local register = specification.register
    local dataset  = specification.dataset
    local field    = specification.field
    if not field or field == "" or not register or register == "" then
        return
    end
    if not dataset or dataset == "" then
        dataset = v_all
    end
    -- could be metatable magic
    local s = specifications[register]
    if not s then
        s = { }
        specifications[register] = s
    end
    local d = s[dataset]
    if not d then
        d = { }
        s[dataset] = d
    end
    --
    -- check all
    --
    d.active    = specification.state ~= v_stop
    d.once      = specification.method == v_once or false
    d.field     = field
    d.processor = name ~= register and name or ""
    d.register  = register
    d.dataset   = dataset
    d.done      = d.done or { }
    --
    sequence   = { }
    for register, s in sortedhash(specifications) do
        for dataset, d in sortedhash(s) do
            if d.active then
                sequence[#sequence+1] = d
            end
        end
    end
end

function commands.btxtoregister(dataset,tag)
    for i=1,#sequence do
        local step = sequence[i]
        local dset = step.dataset
        if dset == v_all or dset == dataset then
            local done = step.done
            if not done[tag] then
                local current = datasets[dataset]
                local entry   = current.luadata[tag]
                if entry then
                    local register  = step.register
                    local field     = step.field
                    local processor = step.processor
                    local flusher   = flushers[field] or flushers.default
                    if processor and processor ~= "" then
                        processor = "btx:r:" .. processor
                    end
                    flusher(register,dataset,tag,field,processor,current,entry,current.details[tag])
                end
                done[tag] = true
            end
        end
    end
end
-- context.setregisterentry (
--     { register },
--     {
--         ["entries:1"] = value,
--         ["keys:1"]    = value,
--     }
-- )

local ctx_dosetfastregisterentry = context.dosetfastregisterentry -- register entry key

local p_keywords = lpeg.tsplitat(lpeg.patterns.whitespace^0 * lpeg.P(";") * lpeg.patterns.whitespace^0)
local writer     = publications.serializeauthor

function flushers.default(register,dataset,tag,field,processor,current,entry,detail)
    local k = detail[field] or entry[field]
    if k then
        ctx_dosetfastregisterentry(register,k,"",processor,"")
    end
end

function flushers.author(register,dataset,tag,field,processor,current,entry,detail)
    if detail then
        local author = detail[field]
        if author then
            for i=1,#author do
                local k = writer { author[i] }
                ctx_dosetfastregisterentry(register,k,"",processor,"") -- todo .. sort key
            end
        end
    end
end

function flushers.keywords(register,dataset,tag,field,processor,current,entry,detail)
    if entry then
        local keywords = entry[field]
        if keywords then
            keywords = lpegmatch(p_keywords,keywords)
            for i=1,#keywords do
                local k = keywords[i]
                ctx_dosetfastregisterentry(register,k,"",processor,"")
            end
        end
    end
end

