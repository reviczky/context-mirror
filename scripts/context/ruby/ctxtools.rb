#!/usr/bin/env ruby

# program   : ctxtools
# copyright : PRAGMA Advanced Document Engineering
# version   : 2004-2005
# author    : Hans Hagen
#
# project   : ConTeXt / eXaMpLe
# concept   : Hans Hagen
# info      : j.hagen@xs4all.nl
# www       : www.pragma-ade.com

# This script will harbor some handy manipulations on context
# related files.

# todo: move scite here
#
# todo: move kpse call to kpse class/module, faster and better

# Taco Hoekwater on patterns and lig building (see 'agr'):
#
# Any direct use of a ligature (as accessed by \char or through active
# characters) is wrong and will create faulty hyphenation. Normally,
# when TeX sees "office", it has six tokens, and it knows from the
# patterns that it can hyphenate between the "ff". It will build an
# internal list of four nodes, like this:
#
# [char, o  , ffi ]
# [lig , ffi, c   ,[f,f,i]]
# [char, c  , e   ]
# [char, e  , NULL]
#
# as you can see from the ffi line, it has remembered the original
# characters. While hyphenating, it temporarily changes back to
# that, then re-instates the ligature afterwards.
#
# If you feed it the ligature directly, like so:
#
# [char, o   , ffi ]
# [char, ffi , c   ]
# [char, c   , e   ]
# [char, e   , NULL]
#
# it cannot do that (it tries to hyphenate as if the "ffi" was a
# character), and the result is wrong hyphenation.

banner = ['CtxTools', 'version 1.3.3', '2004/2006', 'PRAGMA ADE/POD']

unless defined? ownpath
    ownpath = $0.sub(/[\\\/][a-z0-9\-]*?\.rb/i,'')
    $: << ownpath
end

require 'base/switch'
require 'base/logger'
require 'base/system'

require 'rexml/document'
require 'net/http'
require 'ftools'
require 'kconv'

exit if defined?(REQUIRE2LIB)

class String

    def i_translate(element, attribute, category)
        self.gsub!(/(<#{element}.*?#{attribute}=)([\"\'])(.*?)\2/) do
            if category.key?($3) then
                # puts "#{element} #{$3} -> #{category[$3]}\n" if element == 'cd:inherit'
                # puts "#{element} #{$3} => #{category[$3]}\n" if element == 'cd:command'
                "#{$1}#{$2}#{category[$3]}#{$2}"
            else
                # puts "#{element} #{$3} -> ?\n" if element == 'cd:inherit'
                # puts "#{element} #{$3} => ?\n" if element == 'cd:command'
                "#{$1}#{$2}#{$3}#{$2}" # unchanged
            end
        end
    end

    def i_load(element, category)
        self.scan(/<#{element}.*?name=([\"\'])(.*?)\1.*?value=\1(.*?)\1/) do
            category[$2] = $3
        end
    end

end

class Commands

    include CommandBase

    public

    def touchcontextfile
        dowithcontextfile(1)
    end

    def contextversion
        dowithcontextfile(2)
    end

    private

    def dowithcontextfile(action)
        maincontextfile = 'context.tex'
        unless FileTest.file?(maincontextfile) then
            begin
                maincontextfile = `kpsewhich -progname=context #{maincontextfile}`.chomp
            rescue
                maincontextfile = ''
            end
        end
        unless maincontextfile.empty? then
            nextcontextfile = maincontextfile.sub(/context\.tex$/,"cont-new.tex")
            case action
                when 1 then
                    touchfile(maincontextfile)
                    touchfile(nextcontextfile,@@newcontextversion)
                when 2 then
                    reportversion(maincontextfile)
                    reportversion(nextcontextfile,@@newcontextversion)
            end
        end

    end

    @@contextversion    = "\\\\contextversion"
    @@newcontextversion = "\\\\newcontextversion"

    def touchfile(filename,command=@@contextversion)

        if FileTest.file?(filename) then
            if data = IO.read(filename) then
                timestamp = Time.now.strftime('%Y.%m.%d %H:%M')
                prevstamp = ''
                begin
                    data.gsub!(/#{command}\{(\d+\.\d+\.\d+.*?)\}/) do
                        prevstamp = $1
                        "#{command.sub(/(\\)+/,"\\")}{#{timestamp}}"
                    end
                rescue
                else
                    begin
                        File.delete(filename+'.old')
                    rescue
                    end
                    begin
                        File.copy(filename,filename+'.old')
                    rescue
                    end
                    begin
                        if f = File.open(filename,'w') then
                            f.puts(data)
                            f.close
                        end
                    rescue
                    end
                end
                if prevstamp.empty? then
                    report("#{filename} is not updated, no timestamp found")
                else
                    report("#{filename} is updated from #{prevstamp} to #{timestamp}")
                end
            end
        else
            report("#{filename} is not found")
        end

    end

    def reportversion(filename,command=@@contextversion)

        version = 'unknown'
        begin
            if FileTest.file?(filename) && IO.read(filename).match(/#{command}\{(\d+\.\d+\.\d+.*?)\}/) then
                version = $1
            end
        rescue
        end
        if @commandline.option("pipe") then
            print version
        else
            report("context version: #{version} (#{filename})")
        end

    end

end

class Commands

    include CommandBase

    public

    def jeditinterface
        editinterface('jedit')
    end

    def bbeditinterface
        editinterface('bbedit')
    end

    def sciteinterface
        editinterface('scite')
    end

    def rawinterface
        editinterface('raw')
    end

    private

    def editinterface(type='raw')

        return unless FileTest.file?("cont-en.xml")

        interfaces = @commandline.arguments

        if interfaces.empty? then
            interfaces = ['en','cz','de','it','nl','ro','fr']
        end

        interfaces.each do |interface|
            begin
                collection = Hash.new
                mappings   = Hash.new
                if f = open("keys-#{interface}.xml") then
                    while str = f.gets do
                        if str =~ /\<cd\:command\s+name=\"(.*?)\"\s+value=\"(.*?)\".*?\>/o then
                            mappings[$1] = $2
                        end
                    end
                    f.close
                    if f = open("cont-en.xml") then
                        while str = f.gets do
                            if str =~ /\<cd\:command\s+name=\"(.*?)\"\s+type=\"environment\".*?\>/o then
                                collection["start#{mappings[$1]}"] = ''
                                collection["stop#{mappings[$1]}"]  = ''
                            elsif str =~ /\<cd\:command\s+name=\"(.*?)\".*?\>/o then
                                collection["#{mappings[$1]}"] = ''
                            end
                        end
                        f.close
                        case type
                            when 'jedit' then
                                if f = open("context-jedit-#{interface}.xml", 'w') then
                                    f.puts("<?xml version='1.0'?>\n\n")
                                    f.puts("<!DOCTYPE MODE SYSTEM 'xmode.dtd'>\n\n")
                                    f.puts("<MODE>\n")
                                    f.puts("  <RULES>\n")
                                    f.puts("    <KEYWORDS>\n")
                                    collection.keys.sort.each do |name|
                                        f.puts("      <KEYWORD2>\\#{name}</KEYWORD2>\n") unless name.empty?
                                    end
                                    f.puts("    </KEYWORDS>\n")
                                    f.puts("  </RULES>\n")
                                    f.puts("</MODE>\n")
                                    f.close
                                end
                            when 'bbedit' then
                                if f = open("context-bbedit-#{interface}.xml", 'w') then
                                    f.puts("<?xml version='1.0'?>\n\n")
                                    f.puts("<key>BBLMKeywordList</key>\n")
                                    f.puts("<array>\n")
                                    collection.keys.sort.each do |name|
                                        f.puts("    <string>\\#{name}</string>\n") unless name.empty?
                                    end
                                    f.puts("</array>\n")
                                    f.close
                                end
                            when 'scite' then
                                if f = open("cont-#{interface}-scite.properties", 'w') then
                                    i = 0
                                    f.write("keywordclass.macros.context.#{interface}=")
                                    collection.keys.sort.each do |name|
                                        unless name.empty? then
                                            if i==0 then
                                                f.write("\\\n    ")
                                                i = 5
                                            else
                                                i = i - 1
                                            end
                                            f.write("#{name} ")
                                        end
                                    end
                                    f.write("\n")
                                    f.close
                                end
                            else # raw
                                collection.keys.sort.each do |name|
                                    puts("\\#{name}\n") unless name.empty?
                                end
                        end
                    end
                end
            end
        end

    end

end

class Commands

    include CommandBase

    public

    def translateinterface

        # since we know what kind of file we're dealing with,
        # we do it quick and dirty instead of using rexml or
        # xslt

        interfaces = @commandline.arguments

        if interfaces.empty? then
            interfaces = ['cz','de','it','nl','ro','fr']
        else
            interfaces.delete('en')
        end

        interfaces.flatten.each do |interface|

            variables, constants, strings, list, data = Hash.new, Hash.new, Hash.new, '', ''

            keyfile, intfile, outfile = "keys-#{interface}.xml", "cont-en.xml", "cont-#{interface}.xml"

            report("generating #{keyfile}")

            begin
                one = "texexec --make --alone --all #{interface}"
                two = "texexec --batch --silent --interface=#{interface} x-set-01"
                if @commandline.option("force") then
                    system(one)
                    system(two)
                elsif not system(two) then
                    system(one)
                    system(two)
                end
            rescue
            end

                unless File.file?(keyfile) then
                report("no #{keyfile} generated")
                next
            end

            report("loading #{keyfile}")

            begin
                list = IO.read(keyfile)
            rescue
                list = empty
            end

            if list.empty? then
                report("error in loading #{keyfile}")
                next
            end

            list.i_load('cd:variable', variables)
            list.i_load('cd:constant', constants)
            list.i_load('cd:command' , strings)
            # list.i_load('cd:element' , strings)

            report("loading #{intfile}")

            begin
                data = IO.read(intfile)
            rescue
                data = empty
            end

            if data.empty? then
                report("error in loading #{intfile}")
                next
            end

            report("translating interface en to #{interface}")

            data.i_translate('cd:string'   , 'value', strings)
            data.i_translate('cd:variable' , 'value', variables)
            data.i_translate('cd:parameter', 'name' , constants)
            data.i_translate('cd:constant' , 'type' , variables)
            data.i_translate('cd:variable' , 'type' , variables)
            data.i_translate('cd:inherit'  , 'name' , strings)
            # data.i_translate('cd:command'  , 'name' , strings)

            data.gsub!(/(\<cd\:interface[^\>]*?language=")en(")/) do
                $1 + interface + $2
            end

            report("saving #{outfile}")

            begin
                if f = File.open(outfile, 'w') then
                    f.write(data)
                    f.close
                end
            rescue
            end

        end

    end

end

class Commands

    include CommandBase

    public

    def purgefiles

        pattern  = @commandline.arguments
        purgeall = @commandline.option("all")
        recurse  = @commandline.option("recurse")

        $dontaskprefixes.push(Dir.glob("mpx-*"))

        if purgeall then
            $dontaskprefixes.push(Dir.glob("*.tex.prep"))
            $dontaskprefixes.push(Dir.glob("*.xml.prep"))
        end

        $dontaskprefixes.flatten!
        $dontaskprefixes.sort!

        if purgeall then
          $forsuresuffixes.push($texnonesuffixes)
          $texnonesuffixes = []
          $forsuresuffixes.flatten!
        end

        if ! pattern || pattern.empty? then
            globbed = if recurse then "**/*.*" else "*.*" end
            files = Dir.glob(globbed)
            report("purging#{if purgeall then ' all' end} temporary files : #{globbed}")
        else
            pattern.each do |pat|
                globbed = if recurse then "**/#{pat}-*.*" else "#{pat}-*.*" end
                files = Dir.glob(globbed)
                globbed = if recurse then "**/#{pat}.*" else "#{pat}.*" end
                files.push(Dir.glob(globbed))
            end
            report("purging#{if all then ' all' end} temporary files : #{pattern.join(' ')}")
        end
        files.flatten!
        files.sort!

        $dontaskprefixes.each do |file|
            removecontextfile(file)
        end
        $dontasksuffixes.each do |suffix|
            files.each do |file|
                removecontextfile(file) if file =~ /#{suffix}$/i
            end
        end
        $forsuresuffixes.each do |suffix|
            files.each do |file|
                removecontextfile(file) if file =~ /\.#{suffix}$/i
            end
        end
        files.each do |file|
            if file =~ /(.*?)\.\d+$/o then
                basename = $1
                if file =~ /mp(graph|run)/o || FileTest.file?("#{basename}.mp") then
                    removecontextfile($file)
                end
            end
        end
        $texnonesuffixes.each do |suffix|
            files.each do |file|
                if file =~ /(.*)\.#{suffix}$/i then
                    if FileTest.file?("#{$1}.tex") || FileTest.file?("#{$1}.xml") || FileTest.file?("#{$1}.fo") then
                        keepcontextfile(file)
                    else
                        strippedname = $1.gsub(/\-[a-z]$/io, '')
                        if FileTest.file?("#{strippedname}.tex") || FileTest.file?("#{strippedname}.xml") then
                            keepcontextfile("#{file} (potential result file)")
                        else
                            removecontextfile(file)
                        end
                    end
                end
            end
        end

        files = Dir.glob("*.*")
        $dontasksuffixes.each do |suffix|
            files.each do |file|
                removecontextfile(file) if file =~ /^#{suffix}$/i
            end
        end

        if $removedfiles || $keptfiles || $persistentfiles then
            report("removed files : #{$removedfiles}")
            report("kept files : #{$keptfiles}")
            report("persistent files : #{$persistentfiles}")
            report("reclaimed bytes : #{$reclaimedbytes}")
        end

    end

    private

    $removedfiles    = 0
    $keptfiles       = 0
    $persistentfiles = 0
    $reclaimedbytes  = 0

    $dontaskprefixes = [
        # "tex-form.tex", "tex-edit.tex", "tex-temp.tex",
        "texexec.tex", "texexec.tui", "texexec.tuo",
        "texexec.ps", "texexec.pdf", "texexec.dvi",
        "cont-opt.tex", "cont-opt.bak"
    ]
    $dontasksuffixes = [
        "mp(graph|run)\\.mp", "mp(graph|run)\\.mpd", "mp(graph|run)\\.mpo", "mp(graph|run)\\.mpy",
        "mp(graph|run)\\.\\d+",
        "xlscript\\.xsl"
    ]
    $forsuresuffixes = [
        "tui", "tup", "ted", "tes", "top",
        "log", "tmp", "run", "bck", "rlg",
        "mpt", "mpx", "mpd", "mpo", "ctl",
        "tmp.md5", "tmp.out"
    ]
    $texonlysuffixes = [
        "dvi", "ps", "pdf"
    ]
    $texnonesuffixes = [
        "tuo", "tub", "top"
    ]

    def removecontextfile (filename)
        if filename && FileTest.file?(filename) then
            begin
                filesize = FileTest.size(filename)
                File.delete(filename)
            rescue
                report("problematic : #{filename}")
            else
                if FileTest.file?(filename) then
                    $persistentfiles += 1
                    report("persistent : #{filename}")
                else
                    $removedfiles += 1
                    $reclaimedbytes += filesize
                    report("removed : #{filename}")
                end
            end
        end
    end

    def keepcontextfile (filename)
        if filename && FileTest.file?(filename)  then
            $keptfiles += 1
            report("not removed : #{filename}")
        end
    end

end

#D Documentation can be woven into a source file. The next
#D routine generates a new, \TEX\ ready file with the
#D documentation and source fragments properly tagged. The
#D documentation is included as comment:
#D
#D \starttypen
#D %D ......  some kind of documentation
#D %M ......  macros needed for documenation
#D %S B       begin skipping
#D %S E       end skipping
#D \stoptypen
#D
#D The most important tag is \type {%D}. Both \TEX\ and \METAPOST\
#D files use \type{%} as a comment chacacter, while \PERL, \RUBY\
#D and alike use \type{#}. Therefore \type{#D} is also handled.
#D
#D The generated file gets the suffix \type{ted} and is
#D structured as:
#D
#D \starttypen
#D \startmodule[type=suffix]
#D \startdocumentation
#D \stopdocumentation
#D \startdefinition
#D \stopdefinition
#D \stopmodule
#D \stoptypen
#D
#D Macro definitions specific to the documentation are not
#D surrounded by start||stop commands. The suffix specifaction
#D can be overruled at runtime, but defaults to the file
#D extension. This specification can be used for language
#D depended verbatim typesetting.

class Commands

    include CommandBase

    public

    def documentation
        files = @commandline.arguments
        processtype = @commandline.option("type")
        files.each do |fullname|
            if fullname =~ /(.*)\.(.+?)$/o then
                filename, filesuffix = $1, $2
            else
                filename, filesuffix = fullname, 'tex'
            end
            filesuffix = 'tex' if filesuffix.empty?
            fullname, resultname = "#{filename}.#{filesuffix}", "#{filename}.ted"
            if ! FileTest.file?(fullname)
                report("empty input file #{fullname}")
            elsif ! tex = File.open(fullname)
                report("invalid input file #{fullname}")
            elsif ! ted = File.open(resultname,'w') then
                report("unable to openresult file #{resultname}")
            else
                report("input file : #{fullname}")
                report("output file : #{resultname}")
                nofdocuments, nofdefinitions, nofskips = 0, 0, 0
                skiplevel, indocument, indefinition, skippingbang = 0, false, false, false
                if processtype.empty? then
                  filetype = filesuffix.downcase
                else
                  filetype = processtype.downcase
                end
                report("filetype : #{filetype}")
                # we need to signal to texexec what interface to use
                firstline = tex.gets
                if firstline =~ /^\%.*interface\=/ then
                  ted.puts(firstline)
                else
                  tex.rewind # seek(0)
                end
                ted.puts("\\startmodule[type=#{filetype}]\n")
                while str = tex.gets do
                    if skippingbang then
                        skippingbang = false
                    else
                        str.chomp!
                        str.sub!(/\s*$/o, '')
                        case str
                            when /^[%\#]D/io then
                                if skiplevel == 0 then
                                    someline = if str.length < 3 then "" else str[3,str.length-1] end
                                    if indocument then
                                        ted.puts("#{someline}\n")
                                    else
                                        if indefinition then
                                            ted.puts("\\stopdefinition\n")
                                            indefinition = false
                                        end
                                        unless indocument then
                                            ted.puts("\n\\startdocumentation\n")
                                        end
                                        ted.puts("#{someline}\n")
                                        indocument = true
                                        nofdocuments += 1
                                    end
                                end
                            when /^[%\#]M/io then
                                if skiplevel == 0 then
                                    someline = if str.length < 3 then "" else str[3,str.length-1] end
                                    ted.puts("#{someline}\n")
                                end
                            when /^[%\%]S B/io then
                                skiplevel += 1
                                nofskips += 1
                            when /^[%\%]S E/io then
                                  skiplevel -= 1
                            when /^[%\#]/io then
                                  #nothing
                            when /^eval \'\(exit \$\?0\)\' \&\& eval \'exec perl/o then
                                skippingbang = true
                            else
                                if skiplevel == 0 then
                                    inlocaldocument = indocument
                                    inlocaldocument = false # else first line skipped when not empty
                                    someline = str
                                    if indocument then
                                        ted.puts("\\stopdocumentation\n")
                                        indocument = false
                                    end
                                    if indefinition then
                                        if someline.empty? then
                                            ted.puts("\\stopdefinition\n")
                                            indefinition = false
                                        else
                                            ted.puts("#{someline}\n")
                                        end
                                    elsif ! someline.empty? then
                                        ted.puts("\n\\startdefinition\n")
                                        indefinition = true
                                        if inlocaldocument then
                                            # nothing
                                        else
                                            nofdefinitions += 1
                                            ted.puts("#{someline}\n")
                                        end
                                    end
                                end
                        end
                    end
                end
                if indocument then
                    ted.puts("\\stopdocumentation\n")
                end
                if indefinition then
                    ted.puts("\\stopdefinition\n")
                end
                ted.puts("\\stopmodule\n")
                ted.close

                if nofdocuments == 0 && nofdefinitions == 0 then
                    begin
                        File.delete(resultname)
                    rescue
                    end
                end
                report("documentation sections : #{nofdocuments}")
                report("definition sections : #{nofdefinitions}")
                report("skipped sections : #{nofskips}")
            end
        end
    end

end

#D This feature was needed when \PDFTEX\ could not yet access page object
#D numbers (versions prior to 1.11).

class Commands

    include CommandBase

    public

    def filterpages # temp feature / no reporting
        filename = @commandline.argument('first')
        filename.sub!(/\.([a-z]+?)$/io,'')
        pdffile = "#{filename}.pdf"
        tuofile = "#{filename}.tuo"
        if FileTest.file?(pdffile) then
            begin
                prevline, n = '', 0
                if (pdf = File.open(pdffile)) && (tuo = File.open(tuofile,'a')) then
                    report('filtering page object numbers')
                    pdf.binmode
                    while line = pdf.gets do
                        line.chomp
                        # typical pdftex search
                        if (line =~ /\/Type \/Page/o) && (prevline =~ /^(\d+)\s+0\s+obj/o) then
                            p = $1
                            n += 1
                            tuo.puts("\\objectreference{PDFP}{#{n}}{#{p}}{#{n}}\n")
                        else
                            prevline = line
                        end
                    end
                end
                pdf.close
                tuo.close
                report("number of pages : #{n}")
            rescue
                report("fatal error in filtering pages")
            end
        end
    end

end

# This script is used to generate hyphenation pattern files
# that suit ConTeXt. One reason for independent files is that
# over the years too many uncommunicated changes took place
# as well that inconsistency in content, naming, and location
# in the texmf tree takes more time than I'm willing to spend
# on it. Pattern files are normally shipped for LaTeX (and
# partially plain). A side effect of independent files is that
# we can make them encoding independent.
#
# Maybe I'll make this hyptools.tex

class String

    def markbraces
        level = 0
        self.gsub(/([\{\}])/o) do |chr|
            if    chr == '{' then
                level = level + 1
                chr = "((+#{level}))"
            elsif chr == '}' then
                chr = "((-#{level}))"
                level = level - 1
            end
            chr
        end
    end

    def unmarkbraces
        self.gsub(/\(\(\+\d+?\)\)/o) do
            "{"
        end .gsub(/\(\(\-\d+?\)\)/o) do
            "}"
        end
    end

    def getargument(pattern)
        if self =~ /(#{pattern})\s*\(\(\+(\d+)\)\)(.*?)\(\(\-\2\)\)/m then # no /o
            return $3
        else
            return ""
        end
    end

    def withargument(pattern, &block)
        if self.markbraces =~ /^(.*)(#{pattern}\s*)\(\(\+(\d+)\)\)(.*?)\(\(\-\3\)\)(.*)$/m then # no /o
            "#{$1.unmarkbraces}#{$2}{#{yield($4.unmarkbraces)}}#{$5.unmarkbraces}"
        else
            self
        end
    end

    def filterargument(pattern, &block)
        if self.markbraces =~ /^(.*)(#{pattern}\s*)\(\(\+(\d+)\)\)(.*?)\(\(\-\3\)\)(.*)$/m then # no /o
            yield($4.unmarkbraces)
        else
            self
        end
    end

end

class Language

    include CommandBase

    def initialize(commandline=nil, language='en', filenames=nil, encoding='ec')
        @commandline= commandline
        @language = language
        @filenames = filenames
        @remapping = Array.new
        @demapping = Array.new
        @unicode = Hash.new
        @encoding = encoding
        @data = ''
        @read = ''
        preload_accents()
        preload_unicode() if @commandline.option('utf8')
        case @encoding.downcase
            when 't1', 'ec', 'cork' then preload_vector('ec')
            when 'y', 'texnansi'    then preload_vector('texnansi')
            when 'agr', 'agreek'    then preload_vector('agr')
        end
    end

    def report(str)
        if @commandline then
            @commandline.report(str)
        else
            puts("#{str}\n")
        end
    end

    def remap(from, to)
        @remapping.push([from,to])
    end
    def demap(from, to)
        @demapping.push([from,to])
    end

    def load(filenames=@filenames)
        begin
            if filenames then
                @filenames.each do |fileset|
                    [fileset].flatten.each do |filename|
                        begin
                            if fname = located(filename) then
                                data = IO.read(fname)
                                @data += data.gsub(/\%.*$/, '').gsub(/\\message\{.*?\}/, '')
                                data.gsub!(/(\\patterns|\\hyphenation)\s*\{.*/mo) do '' end
                                @read += "\n% preamble of file #{fname}\n\n#{data}\n"
                                report("file #{fname} is loaded")
                                @data.gsub!(/^[\s\n]+$/mois, '')
                                break # next fileset
                            end
                        rescue
                            report("file #{filename} is not readable")
                        end
                    end
                end
            end
        rescue
        end
    end

    def valid?
        ! @data.empty?
    end

    def convert
        if @data then
            n = 0
            if true then
                report("")
                ["\\patterns","\\hyphenation"].each do |what|
                    @data = @data.withargument(what) do |content|
                        report("converting #{what}")
                        report("")
                        @demapping.each_index do |i|
                            content.gsub!(@demapping[i][0], @demapping[i][1])
                        end
                        content.gsub!(/\\delete\{.*?\}/o) do '' end
                        content.gsub!(/\\keep\{(.*?)\}/o) do $1 end
                        done = false
                        @remapping.each_index do |i|
                            from, to, m = @remapping[i][0], @remapping[i][1], 0
                            content.gsub!(from) do
                                done = true
                                m += 1
                                "[#{i}]"
                            end
                            report("#{m.to_s.rjust(5)} entries remapped to #{to}") unless m == 0
                            n += m
                        end
                        content.gsub!(/\[(\d+)\]/o) do
                            @remapping[$1.to_i][1]
                        end
                        report("      nothing remapped") unless done
                        report("")
                        content.to_s
                    end
                end
            else
                @remapping.each do |k|
                    from, to, m = k[0], k[1], 0
                    @data.gsub!(from) do
                        m += 1
                        to
                    end
                    report("#{m.to_s.rjust(5)} entries remapped to #{to}") unless m == 0
                    n += m
                end
            end
            report("#{n} changes in patterns and exceptions")
            if @commandline.option('utf8') then
                n = 0
                @data.gsub!(/\[(.*?)\]/o) do
                    n += 1
                    @unicode[$1] || $1
                end
                report("#{n} unicode utf8 entries")
            end
            return true
        else
            return false
        end
    end

    def comment(str)
        str.gsub!(/^\n/o, '')
        str.chomp!
        if @commandline.option('xml') then
            "<!-- #{str.strip} -->\n\n"
        else
            "% #{str.strip}\n\n"
        end
    end

    def content(tag, str)
        lst = str.split(/\s+/)
        lst.collect! do |l|
            l.strip
        end
        if lst.length>0 then
            lst = "\n#{lst.join("\n")}\n"
        else
            lst = ""
        end
        if @commandline.option('xml') then
            lst.gsub!(/\[(.*?)\]/o) do
                "&#{$1};"
            end
            "<#{tag}>#{lst}</#{tag}>\n\n"
        else
            "\\#{tag} \{#{lst}\}\n\n"
        end
    end

    def banner
        if @commandline.option('xml') then
            "<?xml version='1.0' standalone='yes' ?>\n\n"
        end
    end

    def triggerunicode
        return
        if @commandline.option('utf8') then
            "% xetex needs utf8 encoded patterns and for patterns\n" +
            "% coded as such we need to enable this regime when\n" +
            "% not in xetex; this code will be moved into context\n" +
            "% as soon as we've spread the generic patterns\n" +
            "\n" +
            "\\ifx\\XeTeXversion\\undefined \\else\n" +
            "  \\ifx\\enableregime\\undefined \\else\n" +
            "    \\enableregime[utf]\n" +
            "  \\fi\n" +
            "\\fi\n" +
            "\n"
        end
    end

    def save
        xml = @commandline.option("xml")

        patname = "lang-#{@language}.pat"
        hypname = "lang-#{@language}.hyp"
        rmename = "lang-#{@language}.rme"
        logname = "lang-#{@language}.log"

        desname = "lang-all.xml"

        @data.gsub!(/\\[nc]\{(.+?)\}/)  do $1    end
        @data.gsub!(/\{\}/)             do ''    end
        @data.gsub!(/\n+/mo)            do "\n"  end
        @read.gsub!(/\n+/mo)            do "\n"  end

        description = ''
        commentfile = rmename.dup

        begin
            desfile = `kpsewhich -progname=context #{desname}`.chomp
            if f = File.new(desfile) then
                if doc = REXML::Document.new(f) then
                    if e = REXML::XPath.first(doc.root,"/descriptions/description[@language='#{@language}']") then
                        description = e.to_s
                    end
                end
            end
        rescue
            description = ''
        else
            unless description.empty? then
                commentfile = desname.dup
                str  = "<!-- copied from lang-all.xml\n\n"
                str << "<?xml version='1.0' standalone='yes'?>\n\n"
                str << description.chomp
                str << "\n\nend of copy -->\n"
                str.gsub!(/^/io, "% ") unless @commandline.option('xml')
                description =  comment("begin description data")
                description << str + "\n"
                description << comment("end description data")
                report("description found for language #{@language}")
            end
        end

        begin
            if description.empty? || @commandline.option('log') then
                if f = File.open(logname,'w') then
                    report("saving #{@remapping.length} remap patterns in #{logname}")
                    @remapping.each do |m|
                        f.puts("#{m[0].inspect} => #{m[1]}\n")
                    end
                    f.close
                end
            else
                File.delete(logname) if FileTest.file?(logname)
            end
        rescue
        end

        begin
            if description.empty? || @commandline.option('log') then
                if f = File.open(rmename,'w') then
                    data = @read.dup
                    data.gsub!(/(\s*\n\s*)+/mo, "\n")
                    f << comment("comment copied from public hyphenation files}")
                    f << comment("source of data: #{@filenames.join(' ')}")
                    f << comment("begin original comment")
                    f << "#{data}\n"
                    f << comment("end original comment")
                    f.close
                    report("comment saved in file #{rmename}")
                else
                    report("file #{rmename} is not writable")
                end
            else
                File.delete(rmename) if FileTest.file?(rmename)
            end
        rescue
        end

        begin
            if f = File.open(patname,'w') then
                data = ''
                @data.filterargument('\\patterns') do |content|
                    report("merging patterns")
                    data += content.strip
                end
                data.gsub!(/(\s*\n\s*)+/mo, "\n")

                f << banner
                f << comment("context pattern file, see #{commentfile} for original comment")
                f << comment("source of data: #{@filenames.join(' ')}")
                f << description
                f << comment("begin pattern data")
                f << triggerunicode
                f << content('patterns', data)
                f << comment("end pattern data")
                f.close
                report("patterns saved in file #{patname}")
            else
                report("file #{patname} is not writable")
            end
        rescue
            report("problems with file #{patname}")
        end

        begin
            if f = File.open(hypname,'w') then
                data = ''
                @data.filterargument('\\hyphenation') do |content|
                    report("merging exceptions")
                    data += content.strip
                end
                data.gsub!(/(\s*\n\s*)+/mo, "\n")
                f << banner
                f << comment("context hyphenation file, see #{commentfile} for original comment")
                f << comment("source of data: #{@filenames.join(' ')}")
                f << description
                f << comment("begin hyphenation data")
                f << triggerunicode
                f << content('hyphenation', data)
                f << comment("end hyphenation data")
                f.close
                report("exceptions saved in file #{hypname}")
            else
                report("file #{hypname} is not writable")
            end
        rescue
            report("problems with file #{hypname}")
        end
    end

    def process
        load
        if valid? then
            convert
            save
        else
            report("aborted due to missing files")
        end
    end

    def Language::generate(commandline, language='', filenames='', encoding='ec')
        if ! language.empty? && ! filenames.empty? then
            commandline.report("processing language #{language}")
            commandline.report("")
            language = Language.new(commandline,language,filenames,encoding)
            language.load
            language.convert
            language.save
            commandline.report("")
        end
    end

    private

    def located(filename)
        begin
            fname = `kpsewhich -progname=context #{filename}`.chomp
            if FileTest.file?(fname) then
                report("using file #{fname}")
                return fname
            else
                report("file #{filename} is not present")
                return nil
            end
        rescue
            report("file #{filename} cannot be located using kpsewhich")
            return nil
        end
    end

    def preload_accents

        begin
            if filename = located("enco-acc.tex") then
                if data = IO.read(filename) then
                    report("preloading accent conversions")
                    data.scan(/\\defineaccent\s*\\*(.+?)\s*\{*(.+?)\}*\s*\{\\(.+?)\}/o) do
                        one, two, three = $1, $2, $3
                        one.gsub!(/[\`\~\!\^\*\_\-\+\=\:\;\"\'\,\.\?]/o) do
                            "\\#{one}"
                        end
                        remap(/\\#{one} #{two}/, "[#{three}]")
                        remap(/\\#{one}#{two}/, "[#{three}]")  unless one =~ /[a-zA-Z]/o
                        remap(/\\#{one}\{#{two}\}/, "[#{three}]")
                    end
                end
            end
        rescue
        end

    end

    def preload_unicode

        # \definecharacter Agrave {\uchar0{192}}

        begin
            if filename = located("enco-uc.tex") then
                if data = IO.read(filename) then
                    report("preloading unicode conversions")
                    data.scan(/\\definecharacter\s*(.+?)\s*\{\\uchar\{*(\d+)\}*\s*\{(\d+)\}/o) do
                        one, two, three = $1, $2.to_i, $3.to_i
                        @unicode[one] = [(two*256 + three)].pack("U")
                    end
                end
            end
        rescue
            report("error in loading unicode mapping (#{$!})")
        end

    end

    def preload_vector(encoding='')

        # funny polish

        case @language
            when 'pl' then
                remap(/\/a/, "[aogonek]")    ; remap(/\/A/, "[Aogonek]")
                remap(/\/c/, "[cacute]")     ; remap(/\/C/, "[Cacute]")
                remap(/\/e/, "[eogonek]")    ; remap(/\/E/, "[Eogonek]")
                remap(/\/l/, "[lstroke]")    ; remap(/\/L/, "[Lstroke]")
                remap(/\/n/, "[nacute]")     ; remap(/\/N/, "[Nacute]")
                remap(/\/o/, "[oacute]")     ; remap(/\/O/, "[Oacute]")
                remap(/\/s/, "[sacute]")     ; remap(/\/S/, "[Sacute]")
                remap(/\/x/, "[zacute]")     ; remap(/\/X/, "[Zacute]")
                remap(/\/z/, "[zdotaccent]") ; remap(/\/Z/, "[Zdotaccent]")
            when 'sl' then
                remap(/\"c/,"[ccaron]")  ; remap(/\"C/,"[Ccaron]")
                remap(/\"s/,"[scaron]")  ; remap(/\"S/,"[Scaron]")
                remap(/\"z/,"[zcaron]")  ; remap(/\"Z/,"[Zcaron]")
            when 'da' then
                remap(/X/, "[aeligature]")
                remap(/Y/, "[ostroke]")
                remap(/Z/, "[aring]")
            when 'hu' then
                # nothing
            when 'ca' then
                demap(/\\c\{/, "\\delete{")
            when 'de', 'deo' then
                demap(/\\c\{/, "\\delete{")
                demap(/\\n\{/, "\\keep{")
                remap(/\\3/, "[ssharp]")
                remap(/\\9/, "[ssharp]")
                remap(/\"a/, "[adiaeresis]")
                remap(/\"o/, "[odiaeresis]")
                remap(/\"u/, "[udiaeresis]")
            when 'fr' then
                demap(/\\n\{/, "\\keep{")
                remap(/\\ae/, "[adiaeresis]")
                remap(/\\oe/, "[odiaeresis]")
            when 'la' then
                # \lccode`'=`' somewhere else, todo
                demap(/\\c\{/, "\\delete{")
                remap(/\\a\s*/, "[aeligature]")
                remap(/\\o\s*/, "[oeligature]")
            when 'agr' then
                remap(/\<\'a\|/, "[greekalphaiotasubdasiatonos]")
                # remap(/\<\'a\|/, "[greekdasiatonos][greekAlpha][greekiota]")
                remap(/\>\'a\|/, "[greekalphaiotasubpsilitonos]")
                remap(/\<\`a\|/, "[greekalphaiotasubdasiavaria]")
                remap(/\>\`a\|/, "[greekalphaiotasubpsilivaria]")
                remap(/\<\~a\|/, "[greekalphaiotasubdasiaperispomeni]")
                remap(/\>\~a\|/, "[greekalphaiotasubpsiliperispomeni]")
                remap(/\'a\|/,   "[greekalphaiotasubtonos]")
                remap(/\`a\|/,   "[greekalphaiotasubvaria]")
                remap(/\~a\|/,   "[greekalphaiotasubperispomeni]")
                remap(/\<a\|/,   "[greekalphaiotasubdasia]")
                remap(/\>a\|/,   "[greekalphaiotasubpsili]")
                remap(/a\|/,     "[greekalphaiotasub]")
                remap(/\<\'h\|/, "[greeketaiotasubdasiatonos]")
                remap(/\>\'h\|/, "[greeketaiotasubpsilitonos]")
                remap(/\<\`h\|/, "[greeketaiotasubdasiavaria]")
                remap(/\>\`h\|/, "[greeketaiotasubpsilivaria]")
                remap(/\<\~h\|/, "[greeketaiotasubdasiaperispomeni]")
                remap(/\>\~h\|/, "[greeketaiotasubpsiliperispomeni]")
                remap(/\'h\|/,   "[greeketaiotasubtonos]")
                remap(/\`h\|/,   "[greeketaiotasubvaria]")
                remap(/\~h\|/,   "[greeketaiotasubperispomeni]")
                remap(/\<h\|/,   "[greeketaiotasubdasia]")
                remap(/\>h\|/,   "[greeketaiotasubpsili]")
                remap(/h\|/,     "[greeketaiotasub]")
                remap(/\<'w\|/,  "[greekomegaiotasubdasiatonos]")
                remap(/\>'w\|/,  "[greekomegaiotasubpsilitonos]")
                remap(/\<`w\|/,  "[greekomegaiotasubdasiavaria]")
                remap(/\>`w\|/,  "[greekomegaiotasubpsilivaria]")
                remap(/\<~w\|/,  "[greekomegaiotasubdasiaperispomeni]")
                remap(/\>~w\|/,  "[greekomegaiotasubpsiliperispomeni]")
                remap(/\<w\|/,   "[greekomegaiotasubdasia]")
                remap(/\>w\|/,   "[greekomegaiotasubpsili]")
                remap(/\'w\|/,   "[greekomegaiotasubtonos]")
                remap(/\`w\|/,   "[greekomegaiotasubvaria]")
                remap(/\~w\|/,   "[greekomegaiotasubperispomeni]")
                remap(/w\|/,     "[greekomegaiotasub]")
                remap(/\<\'i/,   "[greekiotadasiatonos]")
                remap(/\>\'i/,   "[greekiotapsilitonos]")
                remap(/\<\`i/,   "[greekiotadasiavaria]")
                remap(/\>\`i/,   "[greekiotapsilivaria]")
                remap(/\<\~i/,   "[greekiotadasiaperispomeni]")
                remap(/\>\~i/,   "[greekiotapsiliperispomeni]")
                remap(/\"\'i/,   "[greekiotadialytikatonos]")
                remap(/\"\`i/,   "[greekiotadialytikavaria]")
                remap(/\"\~i/,   "[greekiotadialytikaperispomeni]")
                remap(/\<i/,     "[greekiotadasia]")
                remap(/\>i/,     "[greekiotapsili]")
                remap(/\'i/,     "[greekiotaoxia]")
                remap(/\`i/,     "[greekiotavaria]")
                remap(/\~i/,     "[greekiotaperispomeni]")
                remap(/\"i/,     "[greekiotadialytika]")
                remap(/\>\~e/,   "[greekepsilonpsiliperispomeni]")
                remap(/\<\~e/,   "[greekepsilondasiaperispomeni]")
                remap(/\<\'e/,   "[greekepsilondasiatonos]")
                remap(/\>\'e/,   "[greekepsilonpsilitonos]")
                remap(/\<\`e/,   "[greekepsilondasiavaria]")
                remap(/\>\`e/,   "[greekepsilonpsilivaria]")
                remap(/\<e/,     "[greekepsilondasia]")
                remap(/\>e/,     "[greekepsilonpsili]")
                remap(/\'e/,     "[greekepsilonoxia]")
                remap(/\`e/,     "[greekepsilonvaria]")
                remap(/\~e/,     "[greekepsilonperispomeni]")
                remap(/\<\'a/,   "[greekalphadasiatonos]")
                remap(/\>\'a/,   "[greekalphapsilitonos]")
                remap(/\<\`a/,   "[greekalphadasiavaria]")
                remap(/\>\`a/,   "[greekalphapsilivaria]")
                remap(/\<\~a/,   "[greekalphadasiaperispomeni]")
                remap(/\>\~a/,   "[greekalphapsiliperispomeni]")
                remap(/\<a/,     "[greekalphadasia]")
                remap(/\>a/,     "[greekalphapsili]")
                remap(/\'a/,     "[greekalphaoxia]")
                remap(/\`a/,     "[greekalphavaria]")
                remap(/\~a/,     "[greekalphaperispomeni]")
                remap(/\<\'h/,   "[greeketadasiatonos]")
                remap(/\>\'h/,   "[greeketapsilitonos]")
                remap(/\<\`h/,   "[greeketadasiavaria]")
                remap(/\>\`h/,   "[greeketapsilivaria]")
                remap(/\<\~h/,   "[greeketadasiaperispomeni]")
                remap(/\>\~h/,   "[greeketapsiliperispomeni]")
                remap(/\<h/,     "[greeketadasia]")
                remap(/\>h/,     "[greeketapsili]")
                remap(/\'h/,     "[greeketaoxia]")
                remap(/\`h/,     "[greeketavaria]")
                remap(/\~h/,     "[greeketaperispomeni]")
                remap(/\<\~o/,   "[greekomicrondasiaperispomeni]")
                remap(/\>\~o/,   "[greekomicronpsiliperispomeni]")
                remap(/\<\'o/,   "[greekomicrondasiatonos]")
                remap(/\>\'o/,   "[greekomicronpsilitonos]")
                remap(/\<\`o/,   "[greekomicrondasiavaria]")
                remap(/\>\`o/,   "[greekomicronpsilivaria]")
                remap(/\<o/,     "[greekomicrondasia]")
                remap(/\>o/,     "[greekomicronpsili]")
                remap(/\'o/,     "[greekomicronoxia]")
                remap(/\`o/,     "[greekomicronvaria]")
                remap(/\~o/,     "[greekomicronperispomeni]")
                remap(/\<\'u/,   "[greekupsilondasiatonos]")
                remap(/\>\'u/,   "[greekupsilonpsilitonos]")
                remap(/\<\`u/,   "[greekupsilondasiavaria]")
                remap(/\>\'u/,   "[greekupsilonpsilivaria]")
                remap(/\<\~u/,   "[greekupsilondasiaperispomeni]")
                remap(/\>\~u/,   "[greekupsilonpsiliperispomeni]")
                remap(/\"\'u/,   "[greekupsilondialytikatonos]")
                remap(/\"\`u/,   "[greekupsilondialytikavaria]")
                remap(/\"\~u/,   "[greekupsilondialytikaperispomeni]")
                remap(/\<u/,     "[greekupsilondasia]")
                remap(/\>u/,     "[greekupsilonpsili]")
                remap(/\'u/,     "[greekupsilonoxia]")
                remap(/\`u/,     "[greekupsilonvaria]")
                remap(/\~u/,     "[greekupsilonperispomeni]")
                remap(/\"u/,     "[greekupsilondiaeresis]")
                remap(/\<\'w/,   "[greekomegadasiatonos]")
                remap(/\>\'w/,   "[greekomegapsilitonos]")
                remap(/\<\`w/,   "[greekomegadasiavaria]")
                remap(/\>\`w/,   "[greekomegapsilivaria]")
                remap(/\<\~w/,   "[greekomegadasiaperispomeni]")
                remap(/\>\~w/,   "[greekomegapsiliperispomeni]")
                remap(/\<w/,     "[greekomegadasia]")
                remap(/\>w/,     "[greekomegapsili]")
                remap(/\'w/,     "[greekomegaoxia]")
                remap(/\`w/,     "[greekomegavaria]")
                remap(/\~w/,     "[greekomegaperispomeni]")
                remap(/\<r/,     "[greekrhodasia]")
                remap(/\>r/,     "[greekrhopsili]")
                remap(/\<\~/,    "[greekdasiaperispomeni]")
                remap(/\>\~/,    "[greekpsiliperispomeni]")
                remap(/\<\'/,    "[greekdasiatonos]")
                remap(/\>\'/,    "[greekpsilitonos]")
                remap(/\<\`/,    "[greekdasiavaria]")
                remap(/\>\`/,    "[greekpsilivaria]")
                remap(/\"\'/,    "[greekdialytikatonos]")
                remap(/\"\`/,    "[greekdialytikavaria]")
                remap(/\"\~/,    "[greekdialytikaperispomeni]")
                remap(/\</,      "[dasia]")
                remap(/\>/,      "[psili]")
                remap(/\'/,      "[oxia]")
                remap(/\`/,      "[greekvaria]")
                remap(/\~/,      "[perispomeni]")
                remap(/\"/,      "[dialytika]")
                # unknown
                remap(/\|/,      "[greekIotadialytika]")
                # next
                remap(/A/, "[greekAlpha]")
                remap(/B/, "[greekBeta]")
                remap(/D/, "[greekDelta]")
                remap(/E/, "[greekEpsilon]")
                remap(/F/, "[greekPhi]")
                remap(/G/, "[greekGamma]")
                remap(/H/, "[greekEta]")
                remap(/I/, "[greekIota]")
                remap(/J/, "[greekTheta]")
                remap(/K/, "[greekKappa]")
                remap(/L/, "[greekLambda]")
                remap(/M/, "[greekMu]")
                remap(/N/, "[greekNu]")
                remap(/O/, "[greekOmicron]")
                remap(/P/, "[greekPi]")
                remap(/Q/, "[greekChi]")
                remap(/R/, "[greekRho]")
                remap(/S/, "[greekSigma]")
                remap(/T/, "[greekTau]")
                remap(/U/, "[greekUpsilon]")
                remap(/W/, "[greekOmega]")
                remap(/X/, "[greekXi]")
                remap(/Y/, "[greekPsi]")
                remap(/Z/, "[greekZeta]")
                remap(/a/, "[greekalpha]")
                remap(/b/, "[greekbeta]")
                remap(/c/, "[greekfinalsigma]")
                remap(/d/, "[greekdelta]")
                remap(/e/, "[greekepsilon]")
                remap(/f/, "[greekphi]")
                remap(/g/, "[greekgamma]")
                remap(/h/, "[greeketa]")
                remap(/i/, "[greekiota]")
                remap(/j/, "[greektheta]")
                remap(/k/, "[greekkappa]")
                remap(/l/, "[greeklambda]")
                remap(/m/, "[greekmu]")
                remap(/n/, "[greeknu]")
                remap(/o/, "[greekomicron]")
                remap(/p/, "[greekpi]")
                remap(/q/, "[greekchi]")
                remap(/r/, "[greekrho]")
                remap(/s/, "[greeksigma]")
                remap(/t/, "[greektau]")
                remap(/u/, "[greekupsilon]")
                remap(/w/, "[greekomega]")
                remap(/x/, "[greekxi]")
                remap(/y/, "[greekpsi]")
                remap(/z/, "[greekzeta]")
            else
        end

        if ! encoding.empty? then
            begin
                filename = `kpsewhich -progname=context enco-#{encoding}.tex`
                if data = IO.read(filename.chomp) then
                    report("preloading #{encoding} character mappings")
                    data.scan(/\\definecharacter\s*([a-zA-Z]+)\s*(\d+)\s*/o) do
                        name, number = $1, $2
                        remap(/\^\^#{sprintf("%02x",number)}/, "[#{name}]")
                        if number.to_i > 127 then
                            remap(/#{sprintf("\\%03o",number)}/, "[#{name}]")
                        end
                    end
                end
            rescue
            end
        end
    end

end

class Commands

    include CommandBase

    public

    @@languagedata = Hash.new

    def patternfiles
        language = @commandline.argument('first')
        if (language == 'all') || language.empty? then
            languages = @@languagedata.keys.sort
        elsif @@languagedata.key?(language) then
            languages = [language]
        else
            languages = []
        end
        languages.each do |language|
            encoding = @@languagedata[language][0] || ''
            files    = @@languagedata[language][1] || []
            Language::generate(self,language,files,encoding)
        end
    end

    private

    # todo: filter the fallback list from context

    # The first entry in the array is the encoding which will be used
    # when interpreting the raw patterns. The second entry is a list of
    # filesets (string|aray), each first match of a set is taken.

    @@languagedata['ba' ] = [ 'ec'      , ['bahyph.tex'] ]
    @@languagedata['ca' ] = [ 'ec'      , ['cahyph.tex'] ]
    @@languagedata['cy' ] = [ 'ec'      , ['cyhyph.tex'] ]
    @@languagedata['cz' ] = [ 'ec'      , ['czhyphen.tex','czhyphen.ex'] ]
    @@languagedata['de' ] = [ 'ec'      , ['dehyphn.tex'] ]
    @@languagedata['deo'] = [ 'ec'      , ['dehypht.tex'] ]
    @@languagedata['da' ] = [ 'ec'      , ['dkspecial.tex','dkcommon.tex'] ]
    # elhyph.tex
    @@languagedata['es' ] = [ 'ec'      , ['eshyph.tex'] ]
    @@languagedata['fi' ] = [ 'ec'      , ['ethyph.tex'] ]
    @@languagedata['fi' ] = [ 'ec'      , ['fihyph.tex'] ]
    @@languagedata['fr' ] = [ 'ec'      , ['frhyph.tex'] ]
    # ghyphen.readme ghyph31.readme grphyph
    @@languagedata['hr' ] = [ 'ec'      , ['hrhyph.tex'] ]
    @@languagedata['hu' ] = [ 'ec'      , ['huhyphn.tex'] ]
    @@languagedata['en' ] = [ 'default' , [['ushyphmax.tex','ushyph.tex','hyphen.tex']] ]
    @@languagedata['us' ] = [ 'default' , [['ushyphmax.tex','ushyph.tex','hyphen.tex']] ]
    # inhyph.tex
    @@languagedata['is' ] = [ 'ec'      , ['ishyph.tex'] ]
    @@languagedata['it' ] = [ 'ec'      , ['ithyph.tex'] ]
    @@languagedata['la' ] = [ 'ec'      , ['lahyph.tex'] ]
    # mnhyph
    @@languagedata['nl' ] = [ 'ec'      , ['nehyph96.tex'] ]
    @@languagedata['no' ] = [ 'ec'      , ['nohyph.tex'] ]
    @@languagedata['agr'] = [ 'agr'     , [['grahyph4.tex','oldgrhyph.tex']] ] # new, todo
    @@languagedata['pl' ] = [ 'ec'      , ['plhyph.tex'] ]
    @@languagedata['pt' ] = [ 'ec'      , ['pthyph.tex'] ]
    @@languagedata['ro' ] = [ 'ec'      , ['rohyph.tex'] ]
    @@languagedata['sl' ] = [ 'ec'      , ['sihyph.tex'] ]
    @@languagedata['sk' ] = [ 'ec'      , ['skhyphen.tex','skhyphen.ex'] ]
    # sorhyph.tex / upper sorbian
    # srhyphc.tex / cyrillic
    @@languagedata['sv' ] = [ 'ec'      , ['svhyph.tex'] ]
    @@languagedata['tr' ] = [ 'ec'      , ['tkhyph.tex'] ]
    @@languagedata['uk' ] = [ 'default' , [['ukhyphen.tex','ukhyph.tex']] ]
end

class Commands

    include CommandBase

    def dpxmapfiles

        force  = @commandline.option("force")

        texmfroot = @commandline.argument('first')
        texmfroot = '.' if texmfroot.empty?
        maproot   = "#{texmfroot.gsub(/\\/,'/')}/fonts/map/pdftex/context"

        if File.directory?(maproot) then
            files = Dir.glob("#{maproot}/*.map")
            if files.size > 0 then
                files.each do |pdffile|
                    next if File.basename(pdffile) == 'pdftex.map'
                    pdffile = File.expand_path(pdffile)
                    dpxfile = File.expand_path(pdffile.sub(/pdftex/i,'dvipdfm'))
                    unless pdffile == dpxfile then
                        begin
                            if data = File.read(pdffile) then
                                report("< #{File.basename(pdffile)} - pdf(e)tex")
                                n = 0
                                data = data.collect do |line|
                                    if line =~ /^[\%\#]+/mo then
                                        ''
                                    else
                                        encoding = if line =~ /([a-z0-9\-]+)\.enc/io        then $1 else ''  end
                                        fontfile = if line =~ /([a-z0-9\-]+)\.(pfb|ttf)/io  then $1 else nil end
                                        metrics  = if line =~ /^([a-z0-9\-]+)[\s\<]+/io     then $1 else nil end
                                        slant    = if line =~ /\"([\d\.]+)\s+SlantFont\"/io then "-s #{$1}" else '' end
                                        if metrics && encoding && fontfile then
                                            n += 1
                                            "#{metrics} #{encoding} #{fontfile} #{slant}"
                                        else
                                            ''
                                        end
                                    end
                                end
                                data.delete_if do |line|
                                    line.gsub(/\s+/,'').empty?
                                end
                                data.collect! do |line|
                                    # remove line with "name name" lines
                                    line.gsub(/^(\S+)\s+\1\s*$/) do
                                        $1
                                    end
                                end
                                begin
                                    if force then
                                        if n > 0 then
                                            File.makedirs(File.dirname(dpxfile))
                                            if f = File.open(dpxfile,'w') then
                                                report("> #{File.basename(dpxfile)} - dvipdfm(x) - #{n}")
                                                f.puts(data)
                                                f.close
                                            else
                                                report("? #{File.basename(dpxfile)} - dvipdfm(x)")
                                            end
                                        else
                                            report("- #{File.basename(dpxfile)} - dvipdfm(x) - no entries")
                                            # begin File.delete(dpxname) ; rescue ; end
                                            if f = File.open(dpxfile,'w') then
                                                f.puts("% no map entries")
                                                f.close
                                            end
                                        end
                                    else
                                        report(". #{File.basename(dpxfile)} - dvipdfm(x) - #{n}")
                                    end
                                rescue
                                    report("error in saving dvipdfm file")
                                end
                            else
                                report("error in loading pdftex file")
                            end
                        rescue
                            report("error in processing pdftex file")
                        end
                    end
                end
                if force then
                    begin
                        report("regenerating database for #{texmfroot}")
                        system("mktexlsr #{texmfroot}")
                    rescue
                    end
                end
            else
                report("no mapfiles found in #{maproot}")
            end
        else
            report("provide proper texmfroot")
        end

    end

end

class Array

    def add_shebang(filename,program)
        unless self[0] =~ /^\#/ then
            self.insert(0,"\#!/usr/env #{program}")
        end
        unless self[2] =~ /^\#.*?copyright\=/ then
            self.insert(1,"\#")
            self.insert(2,"\# copyright=pragma-ade readme=readme.pdf licence=cc-gpl")
            self.insert(3,"") unless self[3].chomp.strip.empty?
            self[2].gsub!(/ +/, ' ')
            return true
        else
            return false
        end
    end

    def add_directive(filename,program)
        unless self[0] =~ /^\%/ then
            self.insert(0,"\% content=#{program}")
        end
        unless self[2] =~ /^\%.*?copyright\=/ then
            self.insert(1,"\%")
            if File.expand_path(filename) =~ /[\\\/](doc|manuals)[\\\/]/ then
                self.insert(2,"\% copyright=pragma-ade readme=readme.pdf licence=cc-by-nc-sa")
            else
                self.insert(2,"\% copyright=pragma-ade readme=readme.pdf licence=cc-gpl")
            end
            self.insert(3,"") unless self[3].chomp.strip.empty?
            self[0].gsub!(/ +/, ' ')
            return true
        else
            return false
        end
    end

    def add_comment(filename)
        if self[0] =~ /<\?xml.*?\?>/ && self[2] !~ /^<\!\-\-.*?copyright\=.*?\-\->/ then
            self.insert(1,"")
            if File.expand_path(filename) =~ /[\\\/](doc|manuals)[\\\/]/ then
                self.insert(2,"<!-- copyright='pragma-ade' readme='readme.pdf' licence='cc-by-nc-sa' -->")
            else
                self.insert(2,"<!-- copyright='pragma-ade' readme='readme.pdf' licence='cc-gpl' -->")
            end
            self.insert(3,"") unless self[3].chomp.strip.empty?
            return true
        else
            return false
        end
    end

end

class Commands

    include CommandBase

    def brandfiles

        force = @commandline.option("force")
        files = @commandline.arguments # Dir.glob("**/*.*")
        done  = false

        files.each do |filename|
            if FileTest.file?(filename) then
                ok = false
                begin
                    data = IO.readlines(filename)
                    case filename
                        when /\.rb$/ then
                            ok = data.add_shebang(filename,'ruby')
                        when /\.pl$/ then
                            ok = data.add_shebang(filename,'perl')
                        when /\.py$/ then
                            ok = data.add_shebang(filename,'python')
                        when /\.lua$/ then
                            ok = data.add_shebang(filename,'lua')
                        when /\.tex$/ then
                            ok = data.add_directive(filename,'tex')
                        when /\.mp$/ then
                            ok = data.add_directive(filename,'metapost')
                        when /\.mf$/ then
                            ok = data.add_directive(filename,'metafont')
                        when /\.(xml|xsl|fo|fx|rlx|rng|exa)$/ then
                            ok = data.add_comment(filename)
                    end
                rescue
                    report("fatal error in processing #{filename}") # maybe this catches the mac problem taco reported
                else
                    if ok then
                        report()
                        report(filename)
                        report()
                        for i in 0..4 do
                           report('  ' + data[i].chomp)
                        end
                        if force && f = File.open(filename,'w') then
                            f.puts data
                            f.close
                        end
                        done = true
                    end
                end
            else
                report("no file named #{filename}")
            end
        end
        report() if done
    end

end

class Commands

    include CommandBase

    # usage   : ctxtools --listentities entities.xml
    # document: <!DOCTYPE something SYSTEM "entities.xml">

    def flushentities(handle,entities,doctype=nil) # 'stylesheet'
        if doctype then
            tab = "\t"
            handle << "<?xml version='1.0' encoding='utf-8'?>\n\n"
            handle << "<!-- !DOCTYPE entities SYSTEM 'entities.xml' -->\n\n"
            handle << "<!DOCTYPE #{doctype} [\n"
        else
            tab = ""
        end
        entities.keys.sort.each do |k|
            handle << "#{tab}<!ENTITY #{k} \"\&\#x#{entities[k]};\">\n"
        end
        if doctype then
            handle << "]>\n"
        end
    end

    def listentities

        filenames  = ['enco-uc.tex','contextnames.txt']
        outputname = @commandline.argument('first')
        doctype    = @commandline.option('doctype')
        entities   = Hash.new

        filenames.each do |filename|
          # filename = `texmfstart tmftools.rb --progname=context #{filename}`.chomp
            filename = `kpsewhich --progname=context #{filename}`.chomp
            if filename and not filename.empty? and FileTest.file?(filename) then
                report("loading #{filename.gsub(/\\/,'/')}") unless outputname.empty?
                IO.readlines(filename).each do |line|
                    case line
                        when /^[\#\%]/io then
                            # skip comment line
                        when /\\definecharacter\s+([a-z]+)\s+\{\\uchar\{*(\d+)\}*\{(\d+)\}\}/io then
                            name, code = $1, ($2.to_i*256 + $3.to_i).to_s
                            entities[name] = code.rjust(4,'0') unless entities.key?(name)
                        when /^([A-F0-9]+)\;([a-z][a-z]+)\;(.*?)\;(.*?)\s*$/io then
                            code, name, adobe, comment = $1, $2, $3, $4
                            entities[name] = code.rjust(4,'0') unless entities.key?(name)
                    end
                end
            end
        end
        if outputname and not outputname.empty? then
            if f = File.open(outputname,'w') then
                report("saving #{entities.size} entities in #{outputname}")
                flushentities(f,entities,doctype)
                f.close
            else
                flushentities($stdout,entities,doctype)
            end
        else
            flushentities($stdout,entities,doctype)
        end
    end

end

class Commands

    include CommandBase

    def platformize

        pattern = if @commandline.arguments.empty? then "*.{rb,pl,py}" else @commandline.arguments end
        recurse = @commandline.option("recurse")
        force = @commandline.option("force")
        pattern = "#{if recurse then '**/' else '' end}#{pattern}"
        Dir.glob(pattern).each do |file|
            if File.file?(file) then
                size = File.size(file)
                data = IO.readlines(file)
                if force then
                    if f = File.open(file,'w')
                        data.each do |line|
                            f.puts(line.chomp)
                        end
                        f.close
                    end
                    if File.size(file) == size then # not robust
                        report("file '#{file}' is unchanged")
                    else
                        report("file '#{file}' is platformized")
                    end
                else
                    report("file '#{file}' is a candidate")
                end
            end
        end
    end

end

class TexDeps

    @@cs_tex = %q/
        above abovedisplayshortskip abovedisplayskip
        abovewithdelims accent adjdemerits advance afterassignment
        aftergroup atop atopwithdelims
        badness baselineskip batchmode begingroup
        belowdisplayshortskip belowdisplayskip binoppenalty botmark
        box boxmaxdepth brokenpenalty
        catcode char chardef cleaders closein closeout clubpenalty
        copy count countdef cr crcr csname
        day deadcycles def defaulthyphenchar defaultskewchar
        delcode delimiter delimiterfactor delimeters
        delimitershortfall delimeters dimen dimendef discretionary
        displayindent displaylimits displaystyle
        displaywidowpenalty displaywidth divide
        doublehyphendemerits dp dump
        edef else emergencystretch end endcsname endgroup endinput
        endlinechar eqno errhelp errmessage errorcontextlines
        errorstopmode escapechar everycr everydisplay everyhbox
        everyjob everymath everypar everyvbox exhyphenpenalty
        expandafter
        fam fi finalhyphendemerits firstmark floatingpenalty font
        fontdimen fontname futurelet
        gdef global group globaldefs
        halign hangafter hangindent hbadness hbox hfil horizontal
        hfill horizontal hfilneg hfuzz hoffset holdinginserts hrule
        hsize hskip hss horizontal ht hyphenation hyphenchar
        hyphenpenalty hyphen
        if ifcase ifcat ifdim ifeof iffalse ifhbox ifhmode ifinner
        ifmmode ifnum ifodd iftrue ifvbox ifvmode ifvoid ifx
        ignorespaces immediate indent input inputlineno input
        insert insertpenalties interlinepenalty
        jobname
        kern
        language lastbox lastkern lastpenalty lastskip lccode
        leaders left lefthyphenmin leftskip leqno let limits
        linepenalty line lineskip lineskiplimit long looseness
        lower lowercase
        mag mark mathaccent mathbin mathchar mathchardef mathchoice
        mathclose mathcode mathinner mathop mathopen mathord
        mathpunct mathrel mathsurround maxdeadcycles maxdepth
        meaning medmuskip message mkern month moveleft moveright
        mskip multiply muskip muskipdef
        newlinechar noalign noboundary noexpand noindent nolimits
        nonscript scriptscript nonstopmode nulldelimiterspace
        nullfont number
        omit openin openout or outer output outputpenalty over
        overfullrule overline overwithdelims
        pagedepth pagefilllstretch pagefillstretch pagefilstretch
        pagegoal pageshrink pagestretch pagetotal par parfillskip
        parindent parshape parskip patterns pausing penalty
        postdisplaypenalty predisplaypenalty predisplaysize
        pretolerance prevdepth prevgraf
        radical raise read relax relpenalty right righthyphenmin
        rightskip romannumeral
        scriptfont scriptscriptfont scriptscriptstyle scriptspace
        scriptstyle scrollmode setbox setlanguage sfcode shipout
        show showbox showboxbreadth showboxdepth showlists showthe
        skewchar skip skipdef spacefactor spaceskip span special
        splitbotmark splitfirstmark splitmaxdepth splittopskip
        string
        tabskip textfont textstyle the thickmuskip thinmuskip time
        toks toksdef tolerance topmark topskip tracingcommands
        tracinglostchars tracingmacros tracingonline tracingoutput
        tracingpages tracingparagraphs tracingrestores tracingstats
        uccode uchyph underline unhbox unhcopy unkern unpenalty
        unskip unvbox unvcopy uppercase
        vadjust valign vbadness vbox vcenter vfil vfill vfilneg
        vfuzz voffset vrule vsize vskip vsplit vss vtop
        wd widowpenalty write
        xdef xleaders xspaceskip
        year
    /.split

    @@cs_etex = %q/
        beginL beginR botmarks
        clubpenalties currentgrouplevel currentgrouptype
        currentifbranch currentiflevel currentiftype
        detokenize dimexpr displaywidowpenalties
        endL endR eTeXrevision eTeXversion everyeof
        firstmarks fontchardp fontcharht fontcharic fontcharwd
        glueexpr glueshrink glueshrinkorder gluestretch
        gluestretchorder gluetomu
        ifcsname ifdefined iffontchar interactionmode
        interactionmode interlinepenalties
        lastlinefit lastnodetype
        marks topmarks middle muexpr mutoglue
        numexpr
        pagediscards parshapedimen parshapeindent parshapelength
        predisplaydirection
        savinghyphcodes savingvdiscards scantokens showgroups
        showifs showtokens splitdiscards splitfirstmarks
        TeXXeTstate tracingassigns tracinggroups tracingifs
        tracingnesting tracingscantokens
        unexpanded unless
        widowpenalties
    /.split

    @@cs_pdftex = %q/
        pdfadjustspacing pdfannot pdfavoidoverfull
        pdfcatalog pdfcompresslevel
        pdfdecimaldigits pdfdest pdfdestmargin
        pdfendlink pdfendthread
        pdffontattr pdffontexpand pdffontname pdffontobjnum pdffontsize
        pdfhorigin
        pdfimageresolution pdfincludechars pdfinfo
        pdflastannot pdflastdemerits pdflastobj
        pdflastvbreakpenalty pdflastxform pdflastximage
        pdflastximagepages pdflastxpos pdflastypos
        pdflinesnapx pdflinesnapy pdflinkmargin pdfliteral
        pdfmapfile pdfmaxpenalty pdfminpenalty pdfmovechars
        pdfnames
        pdfobj pdfoptionpdfminorversion pdfoutline pdfoutput
        pdfpageattr pdfpageheight pdfpageresources pdfpagesattr
        pdfpagewidth pdfpkresolution pdfprotrudechars
        pdfrefobj pdfrefxform pdfrefximage
        pdfsavepos pdfsnaprefpoint pdfsnapx pdfsnapy pdfstartlink
        pdfstartthread
        pdftexrevision pdftexversion pdfthread pdfthreadmargin
        pdfuniqueresname
        pdfvorigin
        pdfxform pdfximage
    /.split

    @@cs_omega = %q/
        odelimiter omathaccent omathchar oradical omathchardef omathcode odelcode
        leftghost rightghost
        charwd charht chardp charit
        localleftbox localrightbox
        localinterlinepenalty localbrokenpenalty
        pagedir bodydir pardir textdir mathdir
        boxdir nextfakemath
        pagewidth pageheight pagerightoffset pagebottomoffset
        nullocp nullocplist ocp externalocp ocplist pushocplist popocplist clearocplists ocptracelevel
        addbeforeocplist addafterocplist removebeforeocplist removeafterocplist
        OmegaVersion
        InputTranslation OutputTranslation DefaultInputTranslation DefaultOutputTranslation
        noInputTranslation noOutputTranslation
        InputMode OutputMode DefaultInputMode DefaultOutputMode
        noInputMode noOutputMode noDefaultInputMode noDefaultOutputMode
    /.split

    @@cs_plain = %q/
        TeX
        bgroup egroup endgraf space empty null
        newcount newdimen newskip newmuskip newbox newtoks newhelp newread newwrite newfam newlanguage newinsert newif
        maxdimen magstephalf magstep
        frenchspacing nonfrenchspacing normalbaselines obeylines obeyspaces raggedright ttraggedright
        thinspace negthinspace enspace enskip quad qquad
        smallskip medskip bigskip removelastskip topglue vglue hglue
        break nobreak allowbreak filbreak goodbreak smallbreak medbreak bigbreak
        line leftline rightline centerline rlap llap underbar strutbox strut
        cases matrix pmatrix bordermatrix eqalign displaylines eqalignno leqalignno
        pageno folio tracingall showhyphens fmtname fmtversion
        hphantom vphantom phantom smash
    /.split

    @@cs_eplain = %q/
        eTeX
        newmarks grouptype interactionmode nodetype iftype
        tracingall loggingall tracingnone
    /.split

    # let's ignore \dimendef etc

    @@primitives_def = "def|edef|xdef|gdef|let|newcount|newdimen|newskip|newbox|newtoks|newmarks|chardef|mathchardef|newconditional"

    @@cs_global  = [@@cs_tex,@@cs_etex,@@cs_pdftex,@@cs_omega].sort.flatten
    @@types      = [['invalid','*'],['okay','='],['forward','>'],['backward','<'],['unknown','?']]

    def initialize(logger=nil)
        @cs_local = Hash.new
        @cs_new   = Hash.new
        @cs_defd  = Hash.new
        @cs_used  = Hash.new
        @filename = 'context.tex'
        @files    = Array.new # keep load order !
        @compact  = false
        @logger   = logger
    end

    def load(filename='context.tex',omitlist=['mult-com.tex'])
        begin
            @filename = filename
            File.open(filename) do |f|
                f.each do |line|
                    if line =~ /^\\input\s+(\S+)\s*/o then
                        @files.push($1) unless omitlist.include?(File.basename($1))
                    end
                end
            end
        rescue
            @files = Array.new
        end
    end

    def analyze
        @files.each do |filename|
            if f = File.open(filename) then
                @logger.report("loading #{filename}") if @logger
                defs, uses, n = 0, 0, 0
                f.each do |line|
                    n += 1
                    case line
                        when /^%/
                            # skip
                        when /\\newif\s*\\if([a-zA-Z@\?\!]+)/ then
                            pushdef(filename,n,"if:#{$1}")
                        when /\\([a-zA-Z@\?\!]+)(true|false)/ then
                            pushuse(filename,n,"if:#{$1}")
                        when /^\s*\\(#{@primitives_def})\\([a-zA-Z@\?\!]{3,})/o
                            pushdef(filename,n,$2)
                        when /\\([a-zA-Z@\?\!]{3,})/o
                            pushuse(filename,n,$1)
                    end
                end
                f.close
            end
        end
    end

    def feedback(compact=false)
        begin
            outputfile = File.basename(@filename).sub(/\.tex$/,'')+'.dep'
            File.open(outputfile,'w') do |f|
                @compact = compact
                @logger.report("saving analysis in #{outputfile}") if @logger
                list, len = @cs_local.keys.sort, 0
                if @compact then
                    list.each do |cs|
                        if cs.length > len then len = cs.length end
                    end
                    len += 1
                else
                    f.puts "<?xml version='1.0'?>\n"
                    f.puts "<dependencies xmlns='http://www.pragma-ade.com/schemas/texdeps.rng' rootfile='#{@filename}'>\n"
                end
                list.each do |cs|
                    if @cs_new.key?(cs) then
                        if @cs_new[cs] == @cs_local[cs] then
                            f.puts some_struc(cs,len,1,some_str(@cs_new,@cs_defd,cs))
                        elsif @cs_new[cs].first == @cs_local[cs].first then
                            f.puts some_struc(cs,len,2,some_str(@cs_new,@cs_defd,cs),some_str(@cs_local,@cs_used,cs))
                        else
                            f.puts some_struc(cs,len,3,some_str(@cs_new,@cs_defd,cs),some_str(@cs_local,@cs_used,cs))
                        end
                    else
                        f.puts some_struc(cs,len,4,some_str(@cs_local,@cs_used,cs))
                    end
                end
                if @compact then
                    # nothing
                else
                    "</dependencies>\n" unless @compact
                end
            end
        rescue
        end
    end

    private

    def some_struc(cs,len,type=1,defstr='',usestr='')
        if @compact then
            "#{cs.ljust(len)} #{@@types[type][1]} #{defstr} #{usestr}"
        else
            "<macro name='#{cs}' type='#{type}'>\n" +
            if defstr.empty? then "  <defined/>\n" else "  <defined>\n#{defstr}  <\defined>\n" end +
            if usestr.empty? then "  <used/>\n"    else "  <used>#{usestr}\n  <\used>\n" end +
            "</macro>\n"
        end
    end

    def some_str(files, lines, cs)
        return '' unless files[cs]
        if @compact then
            str = '[ '
            files[cs].each do |c|
                str += c
                str += " (#{lines[cs][c].join(' ')}) " if lines[cs][c]
                str += ' '
            end
            str += ']'
            str.gsub(/ +/, ' ')
        else
            str = ''
            files[cs].each do |c|
                if lines[cs][c] then
                    str += "    <file name='#{c}'>\n"
                    str += "      "
                    lines[cs][c].each do |l|
                        # str += "      <line n='#{l}'/>\n"
                        str += "<line n='#{l}'/>"
                    end
                    str += "\n"
                    str += "    </file>\n"
                else
                    str += "    <file name='#{c}'/>\n"
                end
            end
            str
        end
    end

    def pushdef(filename,n,cs)
        unless @cs_new.key?(cs) then
            @cs_new[cs] = Array.new
            @cs_defd[cs] = Hash.new unless @cs_defd.key?(cs)
        end
        @cs_defd[cs][filename] = Array.new unless @cs_defd[cs][filename]
        @cs_new[cs].push(filename) unless @cs_new[cs].include?(filename)
        @cs_defd[cs][filename] << n
    end

    def pushuse(filename,n,cs)
        unless @@cs_global.include?(cs.to_s) then
            unless @cs_local[cs] then
                @cs_local[cs] = Array.new
                @cs_used[cs] = Hash.new unless @cs_used.key?(cs)
            end
            @cs_used[cs][filename] = Array.new unless @cs_used[cs][filename]
            @cs_local[cs].push(filename) unless @cs_local[cs].include?(filename)
            @cs_used[cs][filename] << n
        end
    end

end

class Commands

    include CommandBase

    def dependencies

        filename = if @commandline.arguments.empty? then 'context.tex' else @commandline.arguments.first end
        compact  = @commandline.option('compact')

        ['progname=context',''].each do |progname|
            unless FileTest.file?(filename) then
                name = `kpsewhich #{progname} #{filename}`.chomp
                if FileTest.file?(name) then
                    filename = name
                    break
                end
            end
        end

        if FileTest.file?(filename) && deps = TexDeps.new(logger) then
            deps.load
            deps.analyze
            deps.feedback(compact)
        else
            report("unknown file #{filename}")
        end

    end

end

class Commands

    @@re_utf_bom = /^\357\273\277/o # just utf-8

    def disarmutfbom

        if @commandline.arguments.empty? then
            report("provide filename")
        else
            @commandline.arguments.each do |filename|
                report("checking '#{filename}'")
                if FileTest.file?(filename) then
                    begin
                        data = IO.read(filename)
                        if data.sub!(@@re_utf_bom,'') then
                            if @commandline.option('force') then
                                if f = File.open(filename,'wb') then
                                    f << data
                                    f.close
                                    report("bom found and removed")
                                else
                                    report("bom found and removed, but saving file fails")
                                end
                            else
                                report("bom found, use '--force' to remove it")
                            end
                        else
                            report("no bom found")
                        end
                    rescue
                        report("bom found, but removing it fails")
                    end
                else
                    report("provide valid filename")
                end
            end
        end
    end

end

class Commands

    include CommandBase

    def updatecontext

        def fetchfile(site, name, target=nil)
            begin
                http = Net::HTTP.new(site)
                resp, data = http.get(name.gsub(/^\/*/, '/'))
            rescue
                return false
            else
                begin
                    if data then
                        name = File.basename(name)
                        File.open(target || name, 'wb') do |f|
                            f << data
                        end
                    else
                        return false
                    end
                rescue
                    return false
                else
                    return true
                end
            end
        end

        def locatedlocaltree
            return `kpsewhich --expand-var $TEXMFLOCAL`.chomp rescue nil
        end

        def extractarchive(archive)
            if FileTest.file?(archive) then
                begin
                    system("unzip -uo #{archive}")
                rescue
                    report("fatal error, make sure that you have 'unzip' in your path")
                    return false
                else
                    return true
                end
            else
                report("fatal error, '{archive}' has not been downloaded")
                return false
            end
        end

        def remakeformats
            return system("texmfstart texexec --make --all")
        end

        if localtree = locatedlocaltree then
            report("updating #{localtree}")
            begin
                Dir.chdir(localtree)
            rescue
                report("unable to change to #{localtree}")
            else
                archive = 'cont-tmf.zip'
                report("fetching #{archive}")
                unless fetchfile("www.pragma-ade.com","/context/latest/#{archive}") then
                    report("unable to fetch #{archive}")
                    return
                end
                report("extracting #{archive}")
                unless extractarchive(archive) then
                    report("unable to extract #{archive}")
                    return
                end
                report("remaking formats")
                unless remakeformats then
                    report("unable to remak formats")
                end
            end
        else
            report("unable to locate local tree")
        end

    end

end

logger      = Logger.new(banner.shift)
commandline = CommandLine.new

commandline.registeraction('touchcontextfile'  , 'update context version')
commandline.registeraction('contextversion'    , 'report context version')
commandline.registeraction('jeditinterface'    , 'generate jedit syntax files [--pipe]')
commandline.registeraction('bbeditinterface'   , 'generate bbedit syntax files [--pipe]')
commandline.registeraction('sciteinterface'    , 'generate scite syntax files [--pipe]')
commandline.registeraction('rawinterface'      , 'generate raw syntax files [--pipe]')
commandline.registeraction('translateinterface', 'generate interface files (xml) [nl de ..]')
commandline.registeraction('purgefiles'        , 'remove temporary files [--all --recurse] [basename]')
commandline.registeraction('documentation'     , 'generate documentation [--type=] [filename]')
commandline.registeraction('filterpages'       ) # no help, hidden temporary feature
commandline.registeraction('patternfiles'      , 'generate pattern files [--all --xml --utf8] [languagecode]')
commandline.registeraction('dpxmapfiles'       , 'convert pdftex mapfiles to dvipdfmx [--force] [texmfroot]')
commandline.registeraction('listentities'      , 'create doctype entity definition from enco-uc.tex')
commandline.registeraction('brandfiles'        , 'add context copyright notice [--force]')
commandline.registeraction('platformize'       , 'replace line-endings [--recurse --force] [pattern]')
commandline.registeraction('dependencies'      , 'analyze depedencies witin context [--compact] [rootfile]')
commandline.registeraction('updatecontext'     , 'download latest version and remake formats')
commandline.registeraction('disarmutfbom'      , 'remove utf bom [--force]')

commandline.registervalue('type','')

commandline.registerflag('recurse')
commandline.registerflag('force')
commandline.registerflag('pipe')
commandline.registerflag('all')
commandline.registerflag('xml')
commandline.registerflag('log')
commandline.registerflag('utf8')
commandline.registerflag('doctype')

# general

commandline.registeraction('help')
commandline.registeraction('version')

commandline.expand

Commands.new(commandline,logger,banner).send(commandline.action || 'help')
