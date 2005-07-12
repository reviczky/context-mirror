require "base/file"
require "base/logger"

class String

    # real dirty, but inspect does a pretty good escaping but
    # unfortunately puts quotes around the string so we need
    # to strip these

    # def escaped
    #     self.inspect[1,self.inspect.size-2]
    # end

    def escaped
        str = self.inspect ; str[1,str.size-2]
    end

    def splitdata
        if self =~ /^\s*(.*?)\s*\{(.*)\}\s*$/o then
            first, second = $1, $2
            if first.empty? then
                [second.split(/\} \{/o)].flatten
            else
                [first.split(/\s+/o)] + [second.split(/\} \{/o)]
            end
        else
            []
        end
    end

end

class Logger
    def banner(str)
        report(str)
        return "%\n% #{str}\n%\n"
    end
end

class TeXUtil

    class Plugin

        # we need to reset module data for each run; persistent data is
        # possible, just don't reinitialize the data structures that need
        # to be persistent; we reset afterwards becausethen we know what
        # plugins are defined

        def initialize(logger)
            @plugins = Array.new
            @logger = logger
        end

        def reset(name)
            if @plugins.include?(name) then
                begin
                    eval("#{name}").reset(@logger)
                rescue Exception
                    @logger.report("fatal error in resetting plugin")
                end
            else
               @logger.report("no plugin #{name}")
            end
        end

        def resets
            @plugins.each do |p|
                reset(p)
            end
        end

        def register(name, file=nil) # maybe also priority
            if file then
                begin
                    require("#{file.downcase.sub(/\.rb$/,'')}.rb")
                rescue Exception
                    @logger.report("no plugin file #{file} for #{name}")
                else
                    @plugins.push(name)
                end
            else
                @plugins.push(name)
            end
            return self
        end

        def reader(name, data=[])
            if @plugins.include?(name) then
                begin
                    eval("#{name}").reader(@logger,data.flatten)
                rescue Exception
                    @logger.report("fatal error in plugin reader #{name} (#{$!})")
                end
            else
               @logger.report("no plugin #{name}")
            end
        end

        def readers(data=[])
            @plugins.each do |p|
                reader(p,data.flatten)
            end
        end

        def writers(handle)
            @plugins.each do |p|
                begin
                    eval("#{p}").writer(@logger,handle)
                rescue Exception
                    @logger.report("fatal error in plugin writer #{p} (#{$!})")
                end
            end
        end

        def processors
            @plugins.each do |p|
                begin
                    eval("#{p}").processor(@logger)
                rescue Exception
                    @logger.report("fatal error in plugin processor #{p} (#{$!})")
                end
            end
        end

    end

    class Sorter

        def initialize(max=12)
            @rep, @map, @exp = Hash.new, Hash.new, Hash.new
            @max = max
            @rexa, @rexb = nil, nil
        end

        def replacer(from,to='') # and expand
            @rep[from.escaped] = to || ''
        end

        # sorter.reducer('ch', 'c')
        # sorter.reducer('ij', 'y')

        def reducer(from,to='')
            @map[from] = to || ''
        end

        # sorter.expander('aeligature', 'ae')
        # sorter.expander('ijligature', 'y')

        def expander(from,to=nil)
            @exp[from] = to || from || ''
        end

        # shortcut("\\ab\\cd\\e\\f", 'iacute')
        # shortcut("\\\'\\i", 'iacute')
        # shortcut("\\\'i", 'iacute')
        # shortcut("\\\"e", 'ediaeresis')
        # shortcut("\\\'o", 'oacute')

        def shortcut(from,to)
            replacer(from,to)
            expander(to)
        end

        def prepare
            @rexa = /(#{@rep.keys.join('|')})/o
            if @map.size > 0 then
                # watch out, order of match matters
                @rexb = /(\\[a-zA-Z]+|#{@map.keys.join('|')}|.)\s*/o
            else
                @rexb = /(\\[a-zA-Z]+|.)\s*/o
            end
        end

        def remap(str)
            str.gsub(@rexa) do
                @rep[$1.escaped]
            end.gsub(@rexb) do
                token = $1.sub(/\\/o, '')
                if @exp.key?(token) then
                    @exp[token].ljust(@max,' ')
                elsif @map.key?(token) then
                    @map[token].ljust(@max,' ')
                else
                    ''
                end
            end
        end

        def preset(shortcuts=[],expansions=[],reductions=[])
            'a'.upto('z') do |c|
                expander(c)
            end
            shortcuts.each  do |s| shortcut(s[0],s[1]) end
            expansions.each do |e| expander(e[0],e[1]) end
            reductions.each do |r| reducer(r[0],r[1]) end
        end

        def simplify(str)
            s = str.dup
            # ^^
            # s.gsub!(/\^\^([a-f0-9][a-f0-9])/o, $1.hex.chr)
            # \- ||
            s.gsub!(/(\\\-|\|\|)/o) do '-' end
            # {}
            s.gsub!(/\{\}/o) do '' end
            # <*..> (internal xml entity)
            s.gsub!(/<\*(.*?)>/o) do $1 end
            # entities
            s.gsub!(/\\getXMLentity\s*\{(.*?)\}/o) do $1 end
            # elements
            s.gsub!(/\<.*?>/o) do '' end
            # what to do with xml and utf-8
            # \"e etc
            # unknown \cs
            s.gsub!(/\\[a-z][a-z]+\s*\{(.*?)\}/o) do $1 end
            return s
        end

    end

    class Plugin

        module MyFiles

            @@files = Hash.new

            def MyFiles::reset(logger)
                @@files = Hash.new
            end

            def MyFiles::reader(logger,data)
                case data[0]
                    when 'b', 'e' then
                        if @@files.key?(data[1]) then
                            @@files[data[1]] += 1
                        else
                            @@files[data[1]] = 1
                        end
                end
            end

            def MyFiles::writer(logger,handle)
                handle << logger.banner("loaded files: #{@@files.size}")
                @@files.keys.sort.each do |k|
                    handle << "% > #{k} #{@@files[k]/2}\n"
                end
            end

            def MyFiles::processor(logger)
                @@files.keys.sort.each do |k|
                    unless (@@files[k] % 2) == 0 then
                        logger.report("check loading of file #{k}, begin/end problem")
                    end
                end
            end

        end

    end

    class Plugin

        module MyCommands

            @@commands = []

            def MyCommands::reset(logger)
                @@commands = []
            end

            def MyCommands::reader(logger,data)
                @@commands.push(data.shift+data.collect do |d| "\{#{d}\}" end.join)
            end

            def MyCommands::writer(logger,handle)
                handle << logger.banner("commands: #{@@commands.size}")
                @@commands.each do |c|
                    handle << "#{c}\n"
                end
            end

            def MyCommands::processor(logger)
            end

        end

    end

    class Plugin

        module MyExtras

            @@programs = []

            def MyExtras::reset(logger)
                @@programs = []
            end

            def MyExtras::reader(logger,data)
                case data[0]
                    when 'p' then
                        @@programs.push(data[1]) if data[0]
                end
            end

            def MyExtras::writer(logger,handle)
                handle << logger.banner("programs: #{@@programs.size}")
                @@programs.each do |p|
                    handle << "% #{p} (#{@@programs[p.to_i]})\n"
                end
            end

            def MyExtras::processor(logger)
                @@programs.each do |p|
                    cmd = "texmfstart #{@@programs[p.to_i]}"
                    logger.report("running #{cmd}")
                    system(cmd)
                end
            end

        end

    end

    class Plugin

        module MySynonyms

            class Synonym

                @@debug = true

                def initialize(t, c, k, d)
                    @type, @command, @key, @sortkey, @data = t, c, k, k, d
                end

                attr_reader :type, :command, :key, :data
                attr_reader :sortkey
                attr_writer :sortkey

                def build(sorter)
                    @sortkey = sorter.remap(sorter.simplify(@key.downcase))
                    if @sortkey.empty? then
                        @sortkey = sorter.remap(@command.downcase)
                    end
                end

                def <=> (other)
                    @sortkey <=> other.sortkey
                end

                def Synonym.flush(list,handle)
                    if @@debug then
                        list.each do |entry|
                            handle << "% [#{entry.sortkey}]\n"
                        end
                    end
                    list.each do |entry|
                        handle << "\\synonymentry{#{entry.type}}{#{entry.command}}{#{entry.key}}{#{entry.data}}\n"
                    end
                end

            end

            @@synonyms = Hash.new

            def MySynonyms::reset(logger)
                @@synonyms = Hash.new
            end

            def MySynonyms::reader(logger,data)
                if data[0] == 'e' then
                    @@synonyms[data[1]] = Array.new unless @@synonyms.key?(data[1])
                    @@synonyms[data[1]].push(Synonym.new(data[1],data[2],data[3],data[4]))
                end
            end

            def MySynonyms::writer(logger,handle)
                if @@synonyms.size > 0 then
                    @@synonyms.keys.sort.each do |s|
                        handle << logger.banner("synonyms: #{s} #{@@synonyms[s].size}")
                        Synonym.flush(@@synonyms[s],handle)
                    end
                end
            end

            def MySynonyms::processor(logger)
                sorter = Sorter.new
                sorter.preset(eval("MyKeys").shortcuts,eval("MyKeys").expansions,eval("MyKeys").reductions)
                sorter.prepare
                @@synonyms.keys.each do |s|
                    @@synonyms[s].each_index do |i|
                        @@synonyms[s][i].build(sorter)
                    end
                    @@synonyms[s] = @@synonyms[s].sort
                end
            end

        end

    end

    class Plugin

        module MyRegisters

            class Register

                @@debug = true

                @@howto = /^(.*?)\:\:(.*)$/o
                @@split = ' && '

                def initialize(state, t, l, k, e, s, p, r)
                    @state, @type, @location, @key, @entry, @seetoo, @page, @realpage = state, t, l, k, e, s, p, r
                    if @key   =~ @@howto then @pagehowto, @key   = $1, $2 else @pagehowto = '' end
                    if @entry =~ @@howto then @texthowto, @entry = $1, $2 else @texthowto = '' end
                    @key = @entry.dup if @key.empty?
                    @sortkey = @key.dup
                    @nofentries, @nofpages = 0, 0
                end

                attr_reader :state, :type, :location, :key, :entry, :seetoo, :page, :realpage, :texthowto, :pagehowto
                attr_reader :sortkey
                attr_writer :sortkey

                def build(sorter)
                    @entry, @key = [@entry, @key].collect do |target|
                        # +a+b+c &a&b&c a+b+c a&b&c
                        case target[0,1]
                            when '&' then target = target.sub(/^./o,'').gsub(/([^\\])\&/o)     do "#{$1}#{@@split}" end
                            when '+' then target = target.sub(/^./o,'').gsub(/([^\\])\+/o)     do "#{$1}#{@@split}" end
                            else          target = target              .gsub(/([^\\])[\&\+]/o) do "#{$1}#{@@split}" end
                        end
                        # {a}{b}{c}
                        # if target =~ /^\{(.*)\}$/o then
                            # $1.split(/\} \{/o).join(@@split) # space between } { is mandate
                        # else
                            target
                        # end
                    end
                    @sortkey = sorter.simplify(@key)
                    @sortkey = @sortkey.split(@@split).collect do |c| sorter.remap(c) end.join(@@split)
                    # if ($Key eq "")  { $Key = SanitizedString($Entry) }
                    # if ($ProcessHigh){ $Key = HighConverted($Key) }
                    @sortkey = [
                        @sortkey.downcase,
                        @sortkey,
                        @texthowto.ljust(10,' '),
                        @state,
                        @realpage.rjust(6,' '),
                        @pagehowto
                    ].join(@@split)
                end

                def <=> (other)
                    @sortkey <=> other.sortkey
                end

                # more module like

                @@savedhowto, @@savedfrom, @@savedto, @@savedentry = '', '', '', '', ''
                @@collapse = false

                def Register.flushsavedline(handle)
                    if @@collapse && ! @@savedfrom.empty? then
                        if ! @@savedto.empty? then
                            handle << "\\registerfrom#{@@savedfrom}"
                            handle << "\\registerto#{@@savedto}"
                        else
                            handle << "\\registerpage#{@@savedfrom}"
                        end
                    end
                    @@savedhowto, @@savedfrom, @@savedto, @@savedentry = '', '', '', ''
                end

                def Register.flush(list,handle)
                    #
                    # alphaclass can go, now flushed per class
                    #
                    if list.size > 0 then
                        @nofentries, @nofpages = 0, 0
                        current, previous, howto  = Array.new, Array.new, Array.new
                        lastpage, lastrealpage = '', ''
                        alphaclass, alpha = '', ''
                        @@savedhowto, @@savedfrom, @@savedto, @@savedentry = '', '', '', ''

                        if @@debug then
                            list.each do |entry|
                                handle << "% [#{entry.sortkey[0,1]}] [#{entry.sortkey.gsub(/#{@@split}/o,'] [')}]\n"
                            end
                        end
                        list.each do |entry|
                            testalpha = entry.sortkey[0,1].downcase
                            if testalpha != alpha.downcase or alphaclass != entry.class then
                                alpha = testalpha
                                alphaclass = entry.class
                                if alpha != ' ' then
                                    flushsavedline(handle)
                                    character = alpha.sub(/([^a-zA-Z])/o) do "\\" + $1 end
                                    handle << "\\registerentry{#{entry.type}}{#{character}}\n"
                                end
                            end
                            current = [entry.entry.split(@@split),'','',''].flatten
                            howto = current.collect do |e|
                                e + '::' + entry.texthowto
                            end
                            if howto[0] == previous[0] then
                                current[0] = ''
                            else
                                previous[0] = howto[0].dup
                                previous[1] = ''
                                previous[2] = ''
                            end
                            if howto[1] == previous[1] then
                                current[1] = ''
                            else
                                previous[1] = howto[1].dup
                                previous[2] = ''
                            end
                            if howto[2] == previous[2] then
                                current[2] = ''
                            else
                                previous[2] = howto[2].dup
                            end
                            copied = false
                            unless current[0].empty? then
                                Register.flushsavedline(handle)
                                handle << "\\registerentrya{#{entry.type}}{#{current[0]}}\n"
                                copied = true
                            end
                            unless current[1].empty? then
                                Register.flushsavedline(handle)
                                handle << "\\registerentryb{#{entry.type}}{#{current[1]}}\n"
                                copied = true
                            end
                            unless current[2].empty? then
                                Register.flushsavedline(handle)
                                handle << "\\registerentryc{#{entry.type}}{#{current[2]}}\n"
                                copied = true
                            end
                            @nofentries += 1 if copied
                            if entry.realpage.to_i == 0 then
                                Register.flushsavedline(handle)
                                handle << "\\registersee{#{entry.type}}{#{entry.pagehowto},#{entry.texthowto}}{#{entry.seetoo}}{#{entry.page}}\n" ;
                                lastpage, lastrealpage = entry.page, entry.realpage
                            elsif @@savedhowto != entry.pagehowto and ! entry.pagehowto.empty? then
                                @@savedhowto = entry.pagehowto
                            end
                            if copied || ! ((lastpage == entry.page) && (lastrealpage == entry.realpage)) then
                                nextentry = "{#{entry.type}}{#{previous[0]}}{#{previous[1]}}{#{previous[2]}}{#{entry.pagehowto},#{entry.texthowto}}"
                                savedline = "{#{entry.type}}{#{@@savedhowto},#{entry.texthowto}}{#{entry.location}}{#{entry.page}}{#{entry.realpage}}"
                                if entry.state == 1 then # from
                                    Register.flushsavedline(handle)
                                    handle << "\\registerfrom#{savedline}\n"
                                elsif entry.state == 3 then # to
                                    Register.flushsavedline(handle)
                                    handle << "\\registerto#{savedline}\n"
                                elsif @@collapse then
                                    if savedentry != nextentry then
                                        savedFrom = savedline
                                    else
                                        savedTo, savedentry = savedline, nextentry
                                    end
                                else
                                    handle << "\\registerpage#{savedline}\n"
                                end
                                @nofpages += 1
                                lastpage, lastrealpage = entry.page, entry.realpage
                            end
                        end
                        Register.flushsavedline(handle)
                    end
                end

            end

            @@registers = Hash.new

            def MyRegisters::reset(logger)
                @@registers = Hash.new
            end

            def MyRegisters::reader(logger,data)
                case data[0]
                    when 'f' then
                        @@registers[data[1]] = Array.new unless @@registers.key?(data[1])
                        @@registers[data[1]].push(Register.new(1,data[1],data[2],data[3],data[4],nil,data[5],data[6]))
                    when 'e' then
                        @@registers[data[1]] = Array.new unless @@registers.key?(data[1])
                        @@registers[data[1]].push(Register.new(2,data[1],data[2],data[3],data[4],nil,data[5],data[6]))
                    when 't' then
                        @@registers[data[1]] = Array.new unless @@registers.key?(data[1])
                        @@registers[data[1]].push(Register.new(3,data[1],data[2],data[3],data[4],nil,data[5],data[6]))
                    when 's' then
                        @@registers[data[1]] = Array.new unless @@registers.key?(data[1])
                        @@registers[data[1]].push(Register.new(4,data[1],data[2],data[3],data[4],data[5],data[6],nil))
                end
            end

            def MyRegisters::writer(logger,handle)
                if @@registers.size > 0 then
                    @@registers.keys.sort.each do |s|
                        handle << logger.banner("registers: #{s} #{@@registers[s].size}")
                        Register.flush(@@registers[s],handle)
                        # report("register #{@@registers[s].class}: #{@@registers[s].@nofentries} entries and #{@@registers[s].@nofpages} pages")
                    end
                end
            end

            def MyRegisters::processor(logger)
                sorter = Sorter.new
                sorter.preset(eval("MyKeys").shortcuts,eval("MyKeys").expansions,eval("MyKeys").reductions)
                sorter.prepare
                @@registers.keys.each do |s|
                    @@registers[s].each_index do |i|
                        @@registers[s][i].build(sorter)
                    end
                    @@registers[s] = @@registers[s].sort
                end
            end

        end

    end

    class Plugin

        module MyPlugins

            @@plugins = nil

            def MyPlugins::reset(logger)
                @@plugins = nil
            end

            def MyPlugins::reader(logger,data)
                @@plugins = Plugin.new(logger) unless @@plugins
                case data[0]
                    when 'r' then
                        logger.report("registering plugin #{data[1]}")
                        @@plugins.register(data[1],data[2])
                    when 'd' then
                        begin
                            @@plugins.reader(data[1],data[2,data.length-1])
                        rescue
                            @@plugins.reader(data[1],['error'])
                        end
                end
            end

            def MyPlugins::writer(logger,handle)
                @@plugins.writers(handle) if @@plugins
            end

            def MyPlugins::processor(logger)
                @@plugins.processors if @@plugins
            end

        end

    end

    class Plugin

        module MyKeys

            @@shortcuts  = Array.new
            @@expansions = Array.new
            @@reductions = Array.new

            def MyKeys::shortcuts
                @@shortcuts
            end
            def MyKeys::expansions
                @@expansions
            end
            def MyKeys::reductions
                @@reductions
            end

            def MyKeys::reset(logger)
                @@shortcuts  = Array.new
                @@expansions = Array.new
                @@reductions = Array.new
            end

            def MyKeys::reader(logger,data)
                key = data.shift
                grp = data.shift # language code, todo
                case key
                    when 's' then @@shortcuts.push(data)
                    when 'e' then @@expansions.push(data)
                    when 'r' then @@reductions.push(data)
                end
            end

            def MyKeys::writer(logger,handle)
            end

            def MyKeys::processor(logger)
                logger.report("shortcuts: #{@@shortcuts.size}")   # logger.report(@@shortcuts.inspect)
                logger.report("expansions: #{@@expansions.size}") # logger.report(@@expansions.inspect)
                logger.report("reductions: #{@@reductions.size}") # logger.report(@@reductions.inspect)
            end

        end

    end

    class Converter

        def initialize(logger=nil)
            if @logger = logger then
                def report(str)
                    @logger.report(str)
                end
                def banner(str)
                    @logger.banner(str)
                end
            else
                @logger = self
                def report(str)
                    puts(str)
                end
                def banner(str)
                    puts(str)
                end
            end
            @filename = 'texutil'
            @fatalerror = false
            @plugins = Plugin.new(@logger)
            ['MyFiles', 'MyCommands', 'MySynonyms', 'MyRegisters', 'MyExtras', 'MyPlugins', 'MyKeys'].each do |p|
                @plugins.register(p)
            end
        end

        def loaded(filename)
            begin
                report("parsing file #{filename}")
                File.open(File.suffixed(filename,'tui')).each do |line|
                    case line.chomp
                        when /^f (.*)$/o then @plugins.reader('MyFiles',    $1.splitdata)
                        when /^c (.*)$/o then @plugins.reader('MyCommands', [$1])
                        when /^e (.*)$/o then @plugins.reader('MyExtras',   $1.splitdata)
                        when /^s (.*)$/o then @plugins.reader('MySynonyms', $1.splitdata)
                        when /^r (.*)$/o then @plugins.reader('MyRegisters',$1.splitdata)
                        when /^p (.*)$/o then @plugins.reader('MyPlugins',  $1.splitdata)
                        when /^x (.*)$/o then @plugins.reader('MyKeys',     $1.splitdata)
                        else report("unknown entry #{line[0,1]} in line #{line.chomp}")
                    end
                end
            rescue
                report("fatal error in parsing #{filename}")
                @filename = 'texutil'
            else
                @filename = filename
            end
        end

        def processed
            @plugins.processors
            return true # for the moment
        end

        def saved(filename=@filename)
            if @fatalerror then
                report("fatal error, no tuo file saved")
            else
               begin
                    if f = File.open(File.suffixed(filename,'tuo'),'w') then
                        @plugins.writers(f)
                        f.close
                    end
                rescue
                    report("fatal error when saving file (#{$!})")
                else
                    report("tuo file saved")
                end
            end
            @plugins.resets
        end

        def reset
            @plugins.resets
        end

    end

end
