return {
 ["comment"]="% generated by mtxrun --script pattern --convert",
 ["exceptions"]={
  ["characters"]="adefhorstw",
  ["data"]="hard-ware soft-ware",
  ["n"]=2,
 },
 ["metadata"]={
  ["mnemonic"]="pt",
  ["source"]="hyph-pt",
  ["texcomment"]="% Portuguese Hyphenation Patterns\
% \
% (more info about the licence to be added later)\
% \
% This file is part of hyph-utf8 package and resulted from\
% semi-manual conversions of hyphenation patterns into UTF-8 in June 2008.\
%\
% Source: pthyph.tex (1994-10-13 - date on CTAN) or (1996-07-21 - date in file) - no idea\
% Author: Pedro J. de Rezende <rezende at dcc.unicamp.br>, J.Joao Dias Almeida <jj at di.uminho.pt>\
%\
% The above mentioned file should become obsolete,\
% and the author of the original file should preferaby modify this file instead.\
%\
% Modificatios were needed in order to support native UTF-8 engines,\
% but functionality (hopefully) didn't change in any way, at least not intentionally.\
% This file is no longer stand-alone; at least for 8-bit engines\
% you probably want to use loadhyph-foo.tex (which will load this file) instead.\
%\
% Modifications were done by Jonathan Kew, Mojca Miklavec & Arthur Reutenauer\
% with help & support from:\
% - Karl Berry, who gave us free hands and all resources\
% - Taco Hoekwater, with useful macros\
% - Hans Hagen, who did the unicodifisation of patterns already long before\
%               and helped with testing, suggestions and bug reports\
% - Norbert Preining, who tested & integrated patterns into TeX Live\
%\
% However, the \"copyright/copyleft\" owner of patterns remains the original author.\
%\
% The copyright statement of this file is thus:\
%\
%    Do with this file whatever needs to be done in future for the sake of\
%    \"a better world\" as long as you respect the copyright of original file.\
%    If you're the original author of patterns or taking over a new revolution,\
%    plese remove all of the TUG comments & credits that we added here -\
%    you are the Queen / the King, we are only the servants.\
%\
% If you want to change this file, rather than uploading directly to CTAN,\
% we would be grateful if you could send it to us (http://tug.org/tex-hyphen)\
% or ask for credentials for SVN repository and commit it yourself;\
% we will then upload the whole \"package\" to CTAN.\
%\
% Before a new \"pattern-revolution\" starts,\
% please try to follow some guidelines if possible:\
%\
% - \\lccode is *forbidden*, and I really mean it\
% - all the patterns should be in UTF-8\
% - the only \"allowed\" TeX commands in this file are: \\patterns, \\hyphenation,\
%   and if you really cannot do without, also \\input and \\message\
% - in particular, please no \\catcode or \\lccode changes,\
%   they belong to loadhyph-foo.tex,\
%   and no \\lefthyphenmin and \\righthyphenmin,\
%   they have no influence here and belong elsewhere\
% - \\begingroup and/or \\endinput is not needed\
% - feel free to do whatever you want inside comments\
%\
% We know that TeX is extremely powerful, but give a stupid parser\
% at least a chance to read your patterns.\
%\
% For more unformation see\
%\
%    http://tug.org/tex-hyphen\
%\
%------------------------------------------------------------------------------\
%\
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%\
% The Portuguese TeX hyphenation table.\
% (C) 1996 by  Pedro J. de Rezende (rezende@dcc.unicamp.br)\
%          and J.Joao Dias Almeida (jj@di.uminho.pt)\
% Version: 1.2 Release date: 21/07/96\
%\
% (C) 1994 by Pedro J. de Rezende (rezende@dcc.unicamp.br)\
% Version: 1.1 Release date: 04/12/94\
%\
% (C) 1987 by Pedro J. de Rezende\
% Version: 1.0 Release date: 02/13/87\
%\
% -----------------------------------------------------------------\
% IMPORTANT NOTICE:\
%\
% This program can be redistributed and/or modified under the terms\
% of the LaTeX Project Public License Distributed from CTAN\
% archives in directory macros/latex/base/lppl.txt; either\
% version 1 of the License, or any later version.\
% -----------------------------------------------------------------\
% Remember! If you *must* change it, then call the resulting file \
% something  else and attach your name to your *documented* changes.\
% ======================================================================\
%\
% ",
 },
 ["patterns"]={
  ["characters"]="-abcdefghijklmnopqrstuvwxzáâãçéêíóôõú",
  ["data"]="1b2l 1b2r 1ba 1be 1bi 1bo 1bu 1bá 1bâ 1bã 1bé 1bí 1bó 1bú 1bê 1bõ 1c2h 1c2l 1c2r 1ca 1ce 1ci 1co 1cu 1cá 1câ 1cã 1cé 1cí 1có 1cú 1cê 1cõ 1ça 1çe 1çi 1ço 1çu 1çá 1çâ 1çã 1çé 1çí 1çó 1çú 1çê 1çõ 1d2l 1d2r 1da 1de 1di 1do 1du 1dá 1dâ 1dã 1dé 1dí 1dó 1dú 1dê 1dõ 1f2l 1f2r 1fa 1fe 1fi 1fo 1fu 1fá 1fâ 1fã 1fé 1fí 1fó 1fú 1fê 1fõ 1g2l 1g2r 1ga 1ge 1gi 1go 1gu 1gu4a 1gu4e 1gu4i 1gu4o 1gá 1gâ 1gã 1gé 1gí 1gó 1gú 1gê 1gõ 1ja 1je 1ji 1jo 1ju 1já 1jâ 1jã 1jé 1jí 1jó 1jú 1jê 1jõ 1k2l 1k2r 1ka 1ke 1ki 1ko 1ku 1ká 1kâ 1kã 1ké 1kí 1kó 1kú 1kê 1kõ 1l2h 1la 1le 1li 1lo 1lu 1lá 1lâ 1lã 1lé 1lí 1ló 1lú 1lê 1lõ 1ma 1me 1mi 1mo 1mu 1má 1mâ 1mã 1mé 1mí 1mó 1mú 1mê 1mõ 1n2h 1na 1ne 1ni 1no 1nu 1ná 1nâ 1nã 1né 1ní 1nó 1nú 1nê 1nõ 1p2l 1p2r 1pa 1pe 1pi 1po 1pu 1pá 1pâ 1pã 1pé 1pí 1pó 1pú 1pê 1põ 1qu4a 1qu4e 1qu4i 1qu4o 1ra 1re 1ri 1ro 1ru 1rá 1râ 1rã 1ré 1rí 1ró 1rú 1rê 1rõ 1sa 1se 1si 1so 1su 1sá 1sâ 1sã 1sé 1sí 1só 1sú 1sê 1sõ 1t2l 1t2r 1ta 1te 1ti 1to 1tu 1tá 1tâ 1tã 1té 1tí 1tó 1tú 1tê 1tõ 1v2l 1v2r 1va 1ve 1vi 1vo 1vu 1vá 1vâ 1vã 1vé 1ví 1vó 1vú 1vê 1võ 1w2l 1w2r 1xa 1xe 1xi 1xo 1xu 1xá 1xâ 1xã 1xé 1xí 1xó 1xú 1xê 1xõ 1za 1ze 1zi 1zo 1zu 1zá 1zâ 1zã 1zé 1zí 1zó 1zú 1zê 1zõ a3a a3e a3o c3c e3a e3e e3o i3a i3e i3i i3o i3â i3ê i3ô o3a o3e o3o r3r s3s u3a u3e u3o u3u 1-",
  ["minhyphenmax"]=1,
  ["minhyphenmin"]=1,
  ["n"]=307,
 },
 ["version"]="1.001",
}