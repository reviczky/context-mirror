if not modules then modules = { } end modules ['math-ext'] = {
    version   = 1.001,
    comment   = "companion to math-ini.mkiv",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

-- if needed we can use the info here to set up xetex definition files
-- the "8000 hackery influences direct characters (utf) as indirect \char's

local utf = unicode.utf8

local texsprint, format, utfchar, utfbyte = tex.sprint, string.format, utf.char, utf.byte
local setmathcode, setdelcode = tex.setmathcode, tex.setdelcode

local allocate = utilities.storage.allocate

local trace_defining = false  trackers.register("math.defining", function(v) trace_defining = v end)

local report_math = logs.reporter("mathematics","initializing")

mathematics       = mathematics or { }
local mathematics = mathematics

mathematics.extrabase   = 0xFE000 -- here we push some virtuals
mathematics.privatebase = 0xFF000 -- here we push the ex

local families = allocate {
    tf = 0, it = 1, sl = 2, bf = 3, bi = 4, bs = 5, -- no longer relevant
}

local classes = allocate {
    ord       =  0,  -- mathordcomm     mathord
    op        =  1,  -- mathopcomm      mathop
    bin       =  2,  -- mathbincomm     mathbin
    rel       =  3,  -- mathrelcomm     mathrel
    open      =  4,  -- mathopencomm    mathopen
    close     =  5,  -- mathclosecomm   mathclose
    punct     =  6,  -- mathpunctcomm   mathpunct
    alpha     =  7,  -- mathalphacomm   firstofoneargument
    accent    =  8,  -- class 0
    radical   =  9,
    xaccent   = 10,  -- class 3
    topaccent = 11,  -- class 0
    botaccent = 12,  -- class 0
    under     = 13,
    over      = 14,
    delimiter = 15,
    inner     =  0,  -- mathinnercomm   mathinner
    nothing   =  0,  -- mathnothingcomm firstofoneargument
    choice    =  0,  -- mathchoicecomm  @@mathchoicecomm
    box       =  0,  -- mathboxcomm     @@mathboxcomm
    limop     =  1,  -- mathlimopcomm   @@mathlimopcomm
    nolop     =  1,  -- mathnolopcomm   @@mathnolopcomm
}

mathematics.families = families
mathematics.classes  = classes

classes.alphabetic  = classes.alpha
classes.unknown     = classes.nothing
classes.default     = classes.nothing
classes.punctuation = classes.punct
classes.normal      = classes.nothing
classes.opening     = classes.open
classes.closing     = classes.close
classes.binary      = classes.bin
classes.relation    = classes.rel
classes.fence       = classes.unknown
classes.diacritic   = classes.accent
classes.large       = classes.op
classes.variable    = classes.alphabetic
classes.number      = classes.alphabetic

-- there will be proper functions soon (and we will move this code in-line)
-- no need for " in class and family (saves space)

local function delcode(target,family,slot)
    return format('\\Udelcode%s="%X "%X ',target,family,slot)
end
local function mathchar(class,family,slot)
    return format('\\Umathchar "%X "%X "%X ',class,family,slot)
end
local function mathaccent(class,family,slot)
    return format('\\Umathaccent "%X "%X "%X ',0,family,slot) -- no class
end
local function delimiter(class,family,slot)
    return format('\\Udelimiter "%X "%X "%X ',class,family,slot)
end
local function radical(family,slot)
    return format('\\Uradical "%X "%X ',family,slot)
end
local function mathchardef(name,class,family,slot)
    return format('\\Umathchardef\\%s "%X "%X "%X ',name,class,family,slot)
end
local function mathcode(target,class,family,slot)
    return format('\\Umathcode%s="%X "%X "%X ',target,class,family,slot)
end
local function mathtopaccent(class,family,slot)
    return format('\\Umathaccent "%X "%X "%X ',0,family,slot) -- no class
end
if tex.luatexversion > 65 then -- this will disappear at 0.70
    local function mathbotaccent(class,family,slot)
        return format('\\Umathaccent bottom "%X "%X "%X ',0,family,slot) -- no class
    end
else
    local function mathbotaccent(class,family,slot)
        return format('\\Umathbotaccent "%X "%X "%X ',0,family,slot) -- no class
    end
end
local function mathtopdelimiter(class,family,slot)
    return format('\\Udelimiterover "%X "%X ',family,slot) -- no class
end
local function mathbotdelimiter(class,family,slot)
    return format('\\Udelimiterunder "%X "%X ',family,slot) -- no class
end

local escapes = characters.filters.utf.private.escapes

local setmathcharacter, setmathsynonym, setmathsymbol -- once updated we will inline them

if setmathcode then

    setmathcharacter = function(class,family,slot,unicode,firsttime)
        if not firsttime and class <= 7 then
            setmathcode(slot,{class,family,unicode or slot})
        end
    end

    setmathsynonym = function(class,family,slot,unicode,firsttime)
        if not firsttime and class <= 7 then
            setmathcode(slot,{class,family,unicode})
        end
        if class == classes.open or class == classes.close then
            setdelcode(slot,{family,unicode,0,0})
        end
    end

    setmathsymbol = function(name,class,family,slot) -- hex is nicer for tracing
        if class == classes.accent then
            texsprint(format([[\unexpanded\gdef\%s{\Umathaccent 0 "%X "%X }]],name,family,slot))
        elseif class == classes.topaccent then
            texsprint(format([[\unexpanded\gdef\%s{\Umathaccent 0 "%X "%X }]],name,family,slot))
        elseif class == classes.botaccent then
            texsprint(format([[\unexpanded\gdef\%s{\Umathbotaccent 0 "%X "%X }]],name,family,slot))
        elseif class == classes.over then
            texsprint(format([[\unexpanded\gdef\%s{\Udelimiterover "%X "%X }]],name,family,slot))
        elseif class == classes.under then
            texsprint(format([[\unexpanded\gdef\%s{\Udelimiterunder "%X "%X }]],name,family,slot))
        elseif class == classes.open or class == classes.close then
            setdelcode(slot,{family,slot,0,0})
            texsprint(format([[\unexpanded\gdef\%s{\Udelimiter "%X "%X "%X }]],name,class,family,slot))
        elseif class == classes.delimiter then
            setdelcode(slot,{family,slot,0,0})
            texsprint(format([[\unexpanded\gdef\%s{\Udelimiter 0 "%X "%X }]],name,family,slot))
        elseif class == classes.radical then
            texsprint(format([[\unexpanded\gdef\%s{\Uradical "%X "%X }]],name,family,slot))
        else
            -- beware, open/close and other specials should not end up here
            texsprint(format([[\unexpanded\gdef\%s{\Umathchar "%X "%X "%X }]],name,class,family,slot))
        end
    end


else

    setmathcharacter = function(class,family,slot,unicode,firsttime)
        if not firsttime and class <= 7 then
            texsprint(mathcode(slot,class,family,unicode or slot))
        end
    end

    setmathsynonym = function(class,family,slot,unicode,firsttime)
        if not firsttime and class <= 7 then
            texsprint(mathcode(slot,class,family,unicode))
        end
        if class == classes.open or class == classes.close then
            texsprint(delcode(slot,family,unicode))
        end
    end

    setmathsymbol = function(name,class,family,slot)
        if class == classes.accent then
            texsprint(format("\\unexpanded\\xdef\\%s{%s}",name,mathaccent(class,family,slot)))
        elseif class == classes.topaccent then
            texsprint(format("\\unexpanded\\xdef\\%s{%s}",name,mathtopaccent(class,family,slot)))
        elseif class == classes.botaccent then
            texsprint(format("\\unexpanded\\xdef\\%s{%s}",name,mathbotaccent(class,family,slot)))
        elseif class == classes.over then
            texsprint(format("\\unexpanded\\xdef\\%s{%s}",name,mathtopdelimiter(class,family,slot)))
        elseif class == classes.under then
            texsprint(format("\\unexpanded\\xdef\\%s{%s}",name,mathbotdelimiter(class,family,slot)))
        elseif class == classes.open or class == classes.close then
            texsprint(delcode(slot,family,slot))
            texsprint(format("\\unexpanded\\xdef\\%s{%s}",name,delimiter(class,family,slot)))
        elseif class == classes.delimiter then
            texsprint(delcode(slot,family,slot))
            texsprint(format("\\unexpanded\\xdef\\%s{%s}",name,delimiter(0,family,slot)))
        elseif class == classes.radical then
            texsprint(format("\\unexpanded\\xdef\\%s{%s}",name,radical(family,slot)))
        else
            -- beware, open/close and other specials should not end up here
            texsprint(format("\\unexpanded\\xdef\\%s{%s}",name,mathchar(class,family,slot)))
        end
    end

end

local function report(class,family,unicode,name)
    local nametype = type(name)
    if nametype == "string" then
        report_math("%s:%s %s U+%05X (%s) => %s",classname,class,family,unicode,utfchar(unicode),name)
    elseif nametype == "number" then
        report_math("%s:%s %s U+%05X (%s) => U+%05X",classname,class,family,unicode,utfchar(unicode),name)
    else
        report_math("%s:%s %s U+%05X (%s)", classname,class,family,unicode,utfchar(unicode))
    end
end

-- there will be a combined \(math)chardef

function mathematics.define(family)
    family = family or 0
    family = families[family] or family
    local data = characters.data
    for unicode, character in next, data do
        local symbol = character.mathsymbol
        if symbol then
            local other = data[symbol]
            local class = other.mathclass
            if class then
                class = classes[class] or class -- no real checks needed
                if trace_defining then
                    report(class,family,unicode,symbol)
                end
                setmathsynonym(class,family,unicode,symbol)
            end
            local spec = other.mathspec
            if spec then
                for i, m in next, spec do
                    local class = m.class
                    if class then
                        class = classes[class] or class -- no real checks needed
                        setmathsynonym(class,family,unicode,symbol,i)
                    end
                end
            end
        end
        local mathclass = character.mathclass
        local mathspec = character.mathspec
        if mathspec then
            for i, m in next, mathspec do
                local name = m.name
                local class = m.class
                if not class then
                    class = mathclass
                elseif not mathclass then
                    mathclass = class
                end
                if class then
                    class = classes[class] or class -- no real checks needed
                    if name then
                        if trace_defining then
                            report(class,family,unicode,name)
                        end
                        setmathsymbol(name,class,family,unicode)
                    else
                        name = class == classes.variable or class == classes.number and character.adobename
                        if name then
                            if trace_defining then
                                report(class,family,unicode,name)
                            end
                        end
                    end
                    setmathcharacter(class,family,unicode,unicode,i)
                end
            end
        end
        if mathclass then
            local name = character.mathname
            local class = classes[mathclass] or mathclass -- no real checks needed
            if name == false then
                if trace_defining then
                    report(class,family,unicode,name)
                end
                setmathcharacter(class,family,unicode)
            else
                name = name or character.contextname
                if name then
                    if trace_defining then
                        report(class,family,unicode,name)
                    end
                    setmathsymbol(name,class,family,unicode)
                else
                    if trace_defining then
                        report(class,family,unicode,character.adobename)
                    end
                end
                setmathcharacter(class,family,unicode,unicode)
            end
        end
    end
end

-- needed for mathml analysis

function mathematics.utfmathclass(chr, default)
    local cd = characters.data[utfbyte(chr)]
    return (cd and cd.mathclass) or default or "unknown"
end
function mathematics.utfmathstretch(chr, default) -- "h", "v", "b", ""
    local cd = characters.data[utfbyte(chr)]
    return (cd and cd.mathstretch) or default or ""
end
function mathematics.utfmathcommand(chr, default)
    local cd = characters.data[utfbyte(chr)]
    local cmd = cd and cd.mathname
    return cmd or default or ""
end
function mathematics.utfmathfiller(chr, default)
    local cd = characters.data[utfbyte(chr)]
    local cmd = cd and (cd.mathfiller or cd.mathname)
    return cmd or default or ""
end

-- xml

mathematics.xml = { entities = { } }

function mathematics.xml.registerentities()
    local entities = xml.entities
    for name, unicode in next, mathematics.xml.entities do
        if not entities[name] then
            entities[name] = utfchar(unicode)
        end
    end
end

-- helpers

function mathematics.big(tfmdata,unicode,n)
    local t = tfmdata.characters
    local c = t[unicode]
    if c then
        local vv = c.vert_variants or c.next and t[c.next].vert_variants
        if vv then
            local vvn = vv[n]
            return vvn and vvn.glyph or vv[#vv].glyph or unicode
        else
            local next = c.next
            while next do
                if n <= 1 then
                    return next
                else
                    n = n - 1
                    local tn = t[next].next
                    if tn then
                        next = tn
                    else
                        return next
                    end
                end
            end
        end
    end
    return unicode
end

-- plugins (will be proper handler, once we have separated generic from context)

local sequencers    = utilities.sequencers
local appendgroup   = sequencers.appendgroup
local appendaction  = sequencers.appendaction
local mathprocessor = nil

local mathactions = sequencers.reset {
    arguments = "target,original,directives",
}

function fonts.constructors.mathactions(original,target,directives)
    if mathactions.dirty then -- maybe use autocompile
        mathprocessor = sequencers.compile(mathactions)
    end
    mathprocessor(original,target,directives or {})
end

appendgroup(mathactions,"before") -- user
appendgroup(mathactions,"system") -- private
appendgroup(mathactions,"after" ) -- user

function mathematics.initializeparameters(target,original,directives)
    local mathparameters = original.mathparameters
    if mathparameters and next(mathparameters) then
        local _, mp = mathematics.dimensions(mathparameters)
        target.mathparameters = mp -- for ourselves
        target.MathConstants = mp -- for luatex
    end
end

sequencers.appendaction(mathactions,"system","mathematics.initializeparameters")

local how = {
 -- RadicalKernBeforeDegree         = "horizontal",
 -- RadicalKernAfterDegree          = "horizontal",
    RadicalDegreeBottomRaisePercent = "unscaled"
}

function mathematics.scaleparameters(target,original,directives)
    if not directives.disablescaling then
        local mathparameters = target.mathparameters
        if mathparameters and next(mathparameters) then
            local parameters = target.parameters
            local factor  = parameters.factor
            local hfactor = parameters.hfactor
            local vfactor = parameters.vfactor
            for name, value in next, mathparameters do
                local h = how[name]
                if h == "unscaled" then
                    mathparameters[name] = value
                elseif h == "horizontal" then
                    mathparameters[name] = value * hfactor
                elseif h == "vertical"then
                    mathparameters[name] = value * vfactor
                else
                    mathparameters[name] = value * factor
                end
            end
        end
    end
end

sequencers.appendaction(mathactions,"system","mathematics.scaleparameters")

function mathematics.checkaccentbaseheight(target,original,directives)
    local MathConstants = target.MathConstants
    if MathConstants then
        MathConstants.AccentBaseHeight = nil -- safeguard
    end
end

sequencers.appendaction(mathactions,"system","mathematics.checkaccentbaseheight")

function mathematics.checkprivateparameters(target,original,directives)
    local MathConstants = target.MathConstants
    if MathConstants then
        if not MathConstants.FractionDelimiterSize then
            MathConstants.FractionDelimiterSize = 0
        end
        if not MathConstants.FractionDelimiterDisplayStyleSize then
            MathConstants.FractionDelimiterDisplayStyleSize = 0
        end
    end
end

sequencers.appendaction(mathactions,"system","mathematics.checkprivateparameters")

function mathematics.overloadparameters(target,original,directives)
    local mathparameters = target.mathparameters
    if mathparameters and next(mathparameters) then
        local goodies = target.goodies
        if goodies then
            for i=1,#goodies do
                local goodie = goodies[i]
                local mathematics = goodie.mathematics
                local parameters  = mathematics and mathematics.parameters
                if parameters then
                    if trace_defining then
                        report_math("overloading math parameters in '%s' @ %s",target.properties.fullname,target.parameters.size)
                    end
                    for name, value in next, parameters do
                        local tvalue = type(value)
                        if tvalue == "string" then
                            report_math("comment for math parameter '%s': %s",name,value)
                        else
                            local oldvalue = mathparameters[name]
                            local newvalue = oldvalue
                            if oldvalue then
                                if tvalue == "number" then
                                    newvalue = value
                                elseif tvalue == "function" then
                                    newvalue = value(oldvalue,target,original)
                                elseif not tvalue then
                                    newvalue = nil
                                end
                                if trace_defining and oldvalue ~= newvalue then
                                    report_math("overloading math parameter '%s': %s => %s",name,tostring(oldvalue),tostring(newvalue))
                                end
                            else
                                report_math("invalid math parameter '%s'",name)
                            end
                            mathparameters[name] = newvalue
                        end
                    end
                end
            end
        end
    end
end

sequencers.appendaction(mathactions,"system","mathematics.overloadparameters")
