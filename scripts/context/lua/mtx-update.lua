if not modules then modules = { } end modules ['mtx-update'] = {
    version   = 1.002,
    comment   = "companion to mtxrun.lua",
    author    = "Hans Hagen, PRAGMA-ADE, Hasselt NL",
    copyright = "PRAGMA ADE / ConTeXt Development Team",
    license   = "see context related readme files"
}

-- This script is dedicated to Mojca Miklavec, who is the driving force behind
-- moving minimal generation from our internal machines to the context garden.
-- Together with Arthur Reutenauer she made sure that it worked well on all
-- platforms that matter.

local helpinfo = [[
--platform=string     platform (windows, linux, linux-64, osx-intel, osx-ppc, linux-ppc)
--server=string       repository url (rsync://contextgarden.net)
--module=string       repository url (minimals)
--repository=string   specify version (current, experimental)
--context=string      specify version (current, latest, beta, yyyy.mm.dd)
--rsync=string        rsync binary (rsync)
--texroot=string      installation directory (not guessed for the moment)
--engine=string       tex engine (luatex, pdftex, xetex)
--modules=string      extra modules (can be list or 'all')
--fonts=string        additional fonts (can be list or 'all')
--goodies=string      extra binaries (like scite and texworks)
--force               instead of a dryrun, do the real thing
--update              update minimal tree
--make                also make formats and generate file databases
--keep                don't delete unused or obsolete files
--state               update tree using saved state
]]

local application = logs.application {
    name     = "mtx-update",
    banner   = "ConTeXt Minimals Updater 0.30",
    helpinfo = helpinfo,
}

local report = application.report

local format, concat, gmatch, gsub, find = string.format, table.concat, string.gmatch, string.gsub, string.find

scripts         = scripts         or { }
scripts.update  = scripts.update  or { }

minimals        = minimals        or { }
minimals.config = minimals.config or { }

-- this is needed under windows
-- else rsync fails to set the right chmod flags to files

os.setenv("CYGWIN","nontsec")

scripts.update.texformats = {
    "cont-en",
    "cont-nl",
    "cont-cz",
    "cont-de",
    "cont-fa",
    "cont-it",
    "cont-ro",
    "cont-uk",
    "cont-pe",
 -- "cont-xp",
    "mptopdf",
    "plain"
}

scripts.update.mpformats = {
 -- "metafun",
 -- "mpost",
}

-- experimental is not functional at the moment

scripts.update.repositories = {
    "current",
    "experimental"
}

-- more options than just these two are available (no idea why this is here)

scripts.update.versions = {
    "current",
    "latest"
}

-- list of basic folders that are needed to make a functional distribution

scripts.update.base = {
    { "base/tex/",                "texmf" },
    { "base/metapost/",           "texmf" },
    { "fonts/common/",            "texmf" },
    { "fonts/other/",             "texmf" }, -- not *really* needed, but helpful
    { "context/<version>/",       "texmf-context" },
    { "misc/setuptex/",           "." },
    { "misc/web2c",               "texmf" },
    { "bin/common/<platform>/",   "texmf-<platform>" },
    { "bin/context/<platform>/",  "texmf-<platform>" },
    { "bin/metapost/<platform>/", "texmf-<platform>" },
    { "bin/man/",                 "texmf-<platform>" },
}

-- binaries and font-related files
-- for pdftex we don't need OpenType fonts, for LuaTeX/XeTeX we don't need TFM files

scripts.update.engines = {
    ["luatex"] = {
        { "fonts/new/",               "texmf" },
        { "bin/luatex/<platform>/",   "texmf-<platform>" },
    },
    ["xetex"] = {
        { "base/xetex/",              "texmf" },
        { "fonts/new/",               "texmf" },
        { "bin/luatex/<platform>/",   "texmf-<platform>" }, -- tools
        { "bin/xetex/<platform>/",    "texmf-<platform>" },
    },
    ["pdftex"] = {
        { "fonts/old/",               "texmf" },
        { "bin/luatex/<platform>/",   "texmf-<platform>" }, -- tools
        { "bin/pdftex/<platform>/",   "texmf-<platform>" },
    },
    ["all"] = {
        { "fonts/new/",               "texmf" },
        { "fonts/old/",               "texmf" },
        { "base/xetex/",              "texmf" },
        { "bin/luatex/<platform>/",   "texmf-<platform>" },
        { "bin/xetex/<platform>/",    "texmf-<platform>" },
        { "bin/pdftex/<platform>/",   "texmf-<platform>" },
    },
}

scripts.update.goodies = {
    ["scite"] = {
        { "bin/<platform>/scite/",     "texmf-<platform>" },
    },
    ["texworks"] = {
        { "bin/<platform>/texworks/",  "texmf-<platform>" },
    },
}

scripts.update.platforms = {
    ["mswin"]          = "mswin",
    ["windows"]        = "mswin",
    ["win32"]          = "mswin",
    ["win"]            = "mswin",
    ["linux"]          = "linux",
    ["freebsd"]        = "freebsd",
    ["freebsd-amd64"]  = "freebsd-amd64",
    ["kfreebsd"]       = "kfreebsd-i386",
    ["kfreebsd-i386"]  = "kfreebsd-i386",
    ["kfreebsd-amd64"] = "kfreebsd-amd64",
    ["linux-32"]       = "linux",
    ["linux-64"]       = "linux-64",
    ["linux32"]        = "linux",
    ["linux64"]        = "linux-64",
    ["linux-ppc"]      = "linux-ppc",
    ["ppc"]            = "linux-ppc",
    ["osx"]            = "osx-intel",
    ["macosx"]         = "osx-intel",
    ["osx-intel"]      = "osx-intel",
    ["osx-ppc"]        = "osx-ppc",
    ["osx-powerpc"]    = "osx-ppc",
    ["osx-64"]         = "osx-64",
    ["osxintel"]       = "osx-intel",
    ["osxppc"]         = "osx-ppc",
    ["osxpowerpc"]     = "osx-ppc",
    ["solaris-intel"]  = "solaris-intel",
    ["solaris-sparc"]  = "solaris-sparc",
    ["solaris"]        = "solaris-sparc",
}

scripts.update.selfscripts = {
    "mtxrun",
 -- "luatools",
}

-- the list is filled up later (when we know what modules to download)

scripts.update.modules = {
}

scripts.update.fonts = {
}

function scripts.update.run(str)
    -- important, otherwise formats fly to a weird place
    -- (texlua sets luatex as the engine, we need to reset that or to fix texexec :)
    os.setenv("engine",nil)
    if environment.argument("force") then
        report("run, %s",str)
        os.execute(str)
    else
        report("dry run, %s",str)
    end
end

function scripts.update.fullpath(path)
    if file.is_rootbased_path(path) then
        return path
    else
        return lfs.currentdir() .. "/" .. path
    end
end

function scripts.update.synchronize()

    report("update, start")

    local texroot      = scripts.update.fullpath(states.get("paths.root"))
    local engines      = states.get('engines') or { }
    local platforms    = states.get('platforms') or { }
    local repositories = states.get('repositories')      -- minimals
    local bin          = states.get("rsync.program")     -- rsync
    local url          = states.get("rsync.server")      -- contextgarden.net
    local version      = states.get("context.version")   -- current (or beta)
    local modules      = states.get("modules")           -- modules (third party)
    local fonts        = states.get("fonts")             -- fonts (experimental or special)
    local goodies      = states.get("goodies")           -- goodies (like editors)
    local force        = environment.argument("force")

    bin = gsub(bin,"\\","/")

    if not url:find("::$") then url = url .. "::" end
    local ok = lfs.attributes(texroot,"mode") == "directory"
    if not ok and force then
        dir.mkdirs(texroot)
        ok = lfs.attributes(texroot,"mode") == "directory"
    end

    if force then
        dir.mkdirs(format("%s/%s", texroot, "texmf-cache"))
        dir.mkdirs(format("%s/%s", texroot, "texmf-local"))
        dir.mkdirs(format("%s/%s", texroot, "texmf-project"))
        dir.mkdirs(format("%s/%s", texroot, "texmf-fonts"))
        dir.mkdirs(format("%s/%s", texroot, "texmf-modules"))
    end

    if ok or not force then

        local fetched, individual, osplatform = { }, { }, os.platform

        -- takes a collection as argument and returns a list of folders

        local function collection_to_list_of_folders(collection, platform)
            local archives = {}
            for i=1,#collection do
                local archive = collection[i][1]
                archive = gsub(archive,"<platform>",platform)
                archive = gsub(archive,"<version>",version)
                archives[#archives+1] = archive
            end
            return archives
        end

        -- takes a list of folders as argument and returns a string for rsync
        -- sample input:
        --     {'bin/common', 'bin/context'}
        -- output:
        --     'minimals/current/bin/common minimals/current/bin/context'

        local function list_of_folders_to_rsync_string(list_of_folders)
            local repository  = 'current'
            local prefix = format("%s/%s/", states.get('rsync.module'), repository) -- minimals/current/

            return prefix .. concat(list_of_folders, format(" %s", prefix))
        end

        -- example of usage: print(list_of_folders_to_rsync_string(collection_to_list_of_folders(scripts.update.base, os.platform)))

        -- rename function and add some more functionality:
        --   * recursive/non-recursive (default: non-recursive)
        --   * filter folders or regular files only (default: no filter)
        --   * grep for size of included files (with --stats switch)

        local function get_list_of_files_from_rsync(list_of_folders)
            -- temporary file to store the output of rsync (could be a more random name; watch for overwrites)
            local temp_file = "rsync.tmp.txt"
            -- a set of folders
            local folders = {}
            local command = format("%s %s'%s' > %s", bin, url, list_of_folders_to_rsync_string(list_of_folders), temp_file)
            os.execute(command)
            -- read output of rsync
            local data = io.loaddata(temp_file) or ""
            -- for every line extract the filename
            for chmod, s in data:gmatch("([d%-][rwx%-]+).-(%S+)[\n\r]") do
                -- skip "current" folder
                if s ~= '.' and chmod:len() == 10 then
                    folders[#folders+1] = s
                end
            end
            -- delete the file to which we have put output of rsync
            os.remove(temp_file)
            return folders
        end

        -- rsync://contextgarden.net/minimals/current/modules/

        if modules and type(modules) == "table" then
            -- fetch the list of available modules from rsync server
            local available_modules = get_list_of_files_from_rsync({"modules/"})
            -- hash of requested modules
            -- local h = table.tohash(modules:split(","))
            local asked = table.copy(modules)
            asked.all = nil
            for i=1,#available_modules do
                local s = available_modules[i]
                if modules.all or modules[s] then
                    scripts.update.modules[#scripts.update.modules+1] = { format("modules/%s/",s), "texmf-modules" }
                end
                asked[s] = nil
            end
            if next(asked) then
                report("skipping unknown modules: %s",table.concat(table.sortedkeys(asked),", "))
            end
        end

        -- rsync://contextgarden.net/minimals/current/fonts/extra/

        if fonts and type(fonts) == "table" then
            local available_fonts = get_list_of_files_from_rsync({"fonts/extra/"})
            local asked = table.copy(fonts)
            asked.all = nil
            for i=1,#available_fonts do
                local s = available_fonts[i]
                if fonts.all or fonts[s] then
                    scripts.update.fonts[#scripts.update.fonts+1] = { format("fonts/extra/%s/",s), "texmf" }
                end
                asked[s] = nil
            end
            if next(asked) then
                report("skipping unknown fonts: %s",table.concat(table.sortedkeys(asked),", "))
            end
        end

        local function add_collection(collection,platform)
            if collection and platform then
                platform = scripts.update.platforms[platform]
                if platform then
                    for i=1,#collection do
                        local c = collection[i]
                        local archive = gsub(c[1],"<platform>",platform)
                        local destination = format("%s/%s", texroot, gsub(c[2],"<platform>", platform))
                        destination = gsub(destination,"\\","/")
                        archive = gsub(archive,"<version>",version)
                        if osplatform == "windows" or osplatform == "mswin" then
                            destination = gsub(destination,"([a-zA-Z]):/", "/cygdrive/%1/") -- ^
                        end
                        individual[#individual+1] = { archive, destination }
                    end
                end
            end
        end

        for platform, _ in next, platforms do
            add_collection(scripts.update.base,platform)
        end
        for platform, _ in next, platforms do
            add_collection(scripts.update.modules,platform)
        end
        for platform, _ in next, platforms do
            add_collection(scripts.update.fonts,platform)
        end
        for engine, _ in next, engines do
            for platform, _ in next, platforms do
                add_collection(scripts.update.engines[engine],platform)
            end
        end

        if goodies and type(goodies) == "table" then
            for goodie, _ in next, goodies do
                for platform, _ in next, platforms do
                    add_collection(scripts.update.goodies[goodie],platform)
                end
            end
        end

        local combined = { }
        local update_repositories = scripts.update.repositories
        for i=1,#update_repositories do
            local repository = update_repositories[i]
            if repositories[repository] then
                for _, v in next, individual do
                    local archive, destination = v[1], v[2]
                    local cd = combined[destination]
                    if not cd then
                        cd = { }
                        combined[destination] = cd
                    end
                    cd[#cd+1] = format("%s/%s/%s",states.get('rsync.module'),repository,archive)
                end
            end
        end
        for destination, archive in next, combined do
            local archives, command = concat(archive," "), ""
            local normalflags, deleteflags = states.get("rsync.flags.normal"), ""
            if os.name == "windows" then
                normalflags = normalflags .. " -L" -- no symlinks
            end
            local dryrunflags = ""
            if not environment.argument("force") then
                dryrunflags = "--dry-run"
            end
            if (destination:find("texmf$") or destination:find("texmf%-context$") or destination:find("texmf%-modules$")) and (not environment.argument("keep")) then
                deleteflags = states.get("rsync.flags.delete")
            end
            command = format("%s %s %s %s %s'%s' '%s'", bin, normalflags, deleteflags, dryrunflags, url, archives, destination)
            -- report("running command: %s",command)
            if not fetched[command] then
                scripts.update.run(command,true)
                fetched[command] = command
            end
        end

        local function update_script(script, platform)
            local bin = gsub(bin,"\\","/")
            local texroot = gsub(texroot,"\\","/")
            platform = scripts.update.platforms[platform]
            if platform then
                local command
                if platform == 'mswin' then
                    bin = gsub(bin,"([a-zA-Z]):/", "/cygdrive/%1/")
                    texroot = gsub(texroot,"([a-zA-Z]):/", "/cygdrive/%1/")
                    command = format([[%s -t "%s/texmf-context/scripts/context/lua/%s.lua" "%s/texmf-mswin/bin/"]], bin, texroot, script, texroot)
                else
                    command = format([[%s -tgo --chmod=a+x '%s/texmf-context/scripts/context/lua/%s.lua' '%s/texmf-%s/bin/%s']], bin, texroot, script, texroot, platform, script)
                end
                report("updating %s for %s: %s", script, platform, command)
                scripts.update.run(command)
            end
        end

        for platform, _ in next, platforms do
            for i=1, #scripts.update.selfscripts do
                update_script(scripts.update.selfscripts[i],platform)
            end
        end

    else
        report("no valid texroot: %s",texroot)
    end
    if not force then
        report("use --force to really update files")
    end

    resolvers.load_tree(texroot) -- else we operate in the wrong tree

    -- update filename database for pdftex/xetex
    scripts.update.run(format('mtxrun --tree="%s" --direct --resolve mktexlsr',texroot))
    -- update filename database for luatex
    scripts.update.run(format('mtxrun --tree="%s" --generate',texroot))

    report("update, done")
end

function table.fromhash(t)
    local h = { }
    for k, v in next, t do -- not indexed
        if v then h[#h+1] = k end
    end
    return h
end

-- make the ConTeXt formats
function scripts.update.make()

    report("make, start")

    local force     = environment.argument("force")
    local texroot   = scripts.update.fullpath(states.get("paths.root"))
    local engines   = states.get('engines')
    local goodies   = states.get('goodies')
    local platforms = states.get('platforms')
    local formats   = states.get('formats')

    resolvers.load_tree(texroot)

    scripts.update.run(format('mtxrun --tree="%s" --direct --resolve mktexlsr',texroot))
    scripts.update.run(format('mtxrun --tree="%s" --generate',texroot))

    local askedformats = formats
    local texformats = table.tohash(scripts.update.texformats)
    local mpformats = table.tohash(scripts.update.mpformats)
    for k,v in next, texformats do
        if not askedformats[k] then
            texformats[k] = nil
        end
    end
    for k,v in next, mpformats do
        if not askedformats[k] then
            mpformats[k] = nil
        end
    end
    local formatlist = concat(table.fromhash(texformats), " ")
    if formatlist ~= "" then
        for engine in next, engines do
            if engine == "luatex" then
                scripts.update.run(format('mtxrun --tree="%s" --script context --autogenerate --make',texroot))
            else
                scripts.update.run(format('mtxrun --tree="%s" --script texexec --make --all --%s %s',texroot,engine,formatlist))
            end
        end
    end
    local formatlist = concat(table.fromhash(mpformats), " ")
    if formatlist ~= "" then
        scripts.update.run(format('mtxrun --tree="%s" --script texexec --make --all %s',texroot,formatlist))
    end
    if not force then
        report("make, use --force to really make formats")
    end

    scripts.update.run(format('mtxrun --tree="%s" --direct --resolve mktexlsr',texroot)) -- needed for mpost
    scripts.update.run(format('mtxrun --tree="%s" --generate',texroot))

    report("make, done")
end

scripts.savestate = true

if scripts.savestate then

    states.load("status-of-update.lua")

    -- tag, value, default, persistent

    statistics.starttiming(states)

    states.set("info.version",0.1) -- ok
    states.set("info.count",(states.get("info.count") or 0) + 1,1,false) -- ok
    states.set("info.comment","this file contains the settings of the last 'mtxrun --script update' run",false) -- ok
    states.set("info.date",os.date("!%Y-%m-%d %H:%M:%S")) -- ok

    states.set("rsync.program", environment.argument("rsync"), "rsync", true) -- ok
    states.set("rsync.server", environment.argument("server"), "contextgarden.net::", true) -- ok
    states.set("rsync.module", environment.argument("module"), "minimals", true) -- ok
    states.set("rsync.flags.normal", environment.argument("flags"), "-rpztlv", true) -- ok
    states.set("rsync.flags.delete", nil, "--delete", true) -- ok

    states.set("paths.root", environment.argument("texroot"), "tex", true) -- ok

    states.set("context.version", environment.argument("context"), "current", true) -- ok

    local valid = table.tohash(scripts.update.repositories)
    for r in gmatch(environment.argument("repository") or "current","([^, ]+)") do
        if valid[r] then states.set("repositories." .. r, true) end
    end

    local valid = scripts.update.engines
    local engine = environment.argument("engine") or ""
    if engine == "" then
        local e = states.get("engines")
        if not e or not next(e) then
            engine = "all"
        end
    end
    if engine ~= "" then
        for r in gmatch(engine,"([^, ]+)") do
            if r == "all" then
                for k, v in next, valid do
                    if k ~= "all" then
                        states.set("engines." .. k, true)
                    end
                end
                break
            elseif valid[r] then
                states.set("engines." .. r, true)
            end
        end
    end

    local valid = scripts.update.platforms
    for r in gmatch(environment.argument("platform") or os.platform,"([^, ]+)") do
        if valid[r] then states.set("platforms." .. r, true) end
    end

    local valid = table.tohash(scripts.update.texformats)
    for r in gmatch(environment.argument("formats") or "","([^, ]+)") do
        if valid[r] then states.set("formats." .. r, true) end
    end
    local valid = table.tohash(scripts.update.mpformats)
    for r in gmatch(environment.argument("formats") or "","([^, ]+)") do
        if valid[r] then states.set("formats." .. r, true) end
    end

    states.set("formats.cont-en", true)
    states.set("formats.cont-nl", true)
    states.set("formats.metafun", true)

    for r in gmatch(environment.argument("extras") or "","([^, ]+)") do -- for old times sake
        if r ~= "all" and not find(r,"^[a-z]%-") then
            r = "t-" .. r
        end
        states.set("modules." .. r, true)
    end
    for r in gmatch(environment.argument("modules") or "","([^, ]+)") do
        if r ~= "all" and not find(r,"^[a-z]%-") then
            r = "t-" .. r
        end
        states.set("modules." .. r, true)
    end
    for r in gmatch(environment.argument("fonts") or "","([^, ]+)") do
        states.set("fonts." .. r, true)
    end
    for r in gmatch(environment.argument("goodies") or "","([^, ]+)") do
        states.set("goodies." .. r, true)
    end

    report("state, loaded")
    report()

end

if environment.argument("state") then
    environment.setargument("update",true)
    environment.setargument("force",true)
    environment.setargument("make",true)
end

if environment.argument("update") then
    scripts.update.synchronize()
    if environment.argument("make") then
        scripts.update.make()
    end
elseif environment.argument("make") then
    scripts.update.make()
else
    application.help()
end

if scripts.savestate then
    statistics.stoptiming(states)
    states.set("info.runtime",tonumber(statistics.elapsedtime(states)))
    if environment.argument("force") then
        states.save()
        report("state","saved")
    end
end
